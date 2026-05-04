# clustrer_hadoop

Hadoop-кластер в Docker на 3 ноутбуках: **1 мастер + 2 воркера**.

Стек: **Hadoop 3.3.6** (HDFS + YARN + MapReduce) на базе **OpenJDK 11**
(`eclipse-temurin:11-jre-jammy`). Контейнеры на разных ноутбуках общаются
друг с другом через bridge-сеть Docker, проброшенные порты и логические
hostname'ы (`namenode`, `resourcemanager`, `historyserver`, `worker1`,
`worker2`), которые на каждом контейнере резолвятся в LAN-IP реальных
ноутбуков через `extra_hosts`. Никаких экспериментальных режимов Docker
Desktop включать не нужно.

## Что получится

| Ноут       | Контейнеры                                                  |
|------------|-------------------------------------------------------------|
| `master`   | NameNode, SecondaryNameNode, ResourceManager, HistoryServer |
| `worker1`  | DataNode, NodeManager                                       |
| `worker2`  | DataNode, NodeManager                                       |

Веб-интерфейсы (открываются с любого ноута, ходить через IP мастера):

| URL                                | Что показывает          |
|------------------------------------|-------------------------|
| `http://<MASTER_IP>:9870`          | NameNode (HDFS)         |
| `http://<MASTER_IP>:8088`          | ResourceManager (YARN)  |
| `http://<MASTER_IP>:19888`         | JobHistory              |
| `http://<MASTER_IP>:9868`          | SecondaryNameNode       |
| `http://<WORKER_IP>:9864`          | DataNode на воркере     |
| `http://<WORKER_IP>:8042`          | NodeManager на воркере  |

## Что нужно на каждом ноуте

- Windows 10/11 + **Docker Desktop** (с включённым WSL2 backend), либо
  любая ОС с Docker Engine ≥ 24.
- Все 3 ноута в одной локальной сети, видят друг друга по IP
  (проверка: `ping <IP_другого_ноута>` должен идти).
- Открытые порты (Windows Defender / другой firewall) — см. список ниже.
- Минимум ~4 ГБ свободной памяти под Docker.

### Порты, которые надо разрешить в firewall

- **на мастере**: 9000, 9870, 9868, 8030–8033, 8088, 19888, 10020
- **на воркерах**: 9864, 9866, 9867, 8040, 8041, 8042, 13562, 32000–32100

На Windows проще всего временно (на время лабораторной) разрешить весь
трафик от подсети ноутбуков — Defender → Advanced settings → Inbound rules
→ New rule → Custom → Remote IPs.

## Шаг 1. Клонирование репозитория

На каждом из 3 ноутбуков:

```powershell
# В PowerShell или Git Bash
git clone https://github.com/SailorVAC/clustrer_hadoop.git
cd clustrer_hadoop
```

## Шаг 2. Узнать IP всех 3 ноутбуков

В PowerShell на каждом ноуте:

```powershell
ipconfig
```

Найти IPv4-адрес сетевого адаптера, по которому ноуты в одной сети
(обычно `192.168.x.x` или `10.x.x.x`). Запиши три адреса:

```
master   = 192.168.1.10   (например)
worker1  = 192.168.1.11
worker2  = 192.168.1.12
```

## Шаг 3. Создать `.env` на каждом ноуте

Скопируй `.env.example` → `.env` и заполни одинаковыми тремя `*_IP` на
**всех трёх** ноутах.

```powershell
copy .env.example .env
notepad .env
```

```env
MASTER_IP=192.168.1.10
WORKER1_IP=192.168.1.11
WORKER2_IP=192.168.1.12

# только для воркеров: на worker1-ноуте поставь worker1,
# на worker2-ноуте — worker2
NODE_NAME=worker1
```

## Шаг 4. Запустить мастер

На **master**-ноуте:

```powershell
docker compose -f docker-compose.master.yml up -d --build
```

Первый запуск долгий: качается Hadoop (~700 МБ) и собирается образ.
Дождись, пока NameNode будет жив:

```powershell
docker logs -f namenode
# ищи строку: "NameNode RPC up at: master/...:9000"
```

Открой `http://localhost:9870` — должна появиться NameNode UI.

## Шаг 5. Запустить воркеры

На **worker1**-ноуте проверь, что в `.env` стоит `NODE_NAME=worker1`,
и запусти:

```powershell
docker compose -f docker-compose.worker.yml up -d --build
```

Аналогично на **worker2**-ноуте (с `NODE_NAME=worker2`).

Воркеры не стартуют, пока NameNode на мастере не примет соединения —
entrypoint ждёт `master:9000`. Это нормально.

## Шаг 6. Проверить, что кластер собрался

С мастера:

```powershell
docker exec namenode hdfs dfsadmin -report
docker exec resourcemanager yarn node -list
```

В отчёте должно быть **2 живых DataNode** (`worker1`, `worker2`) и
**2 NodeManager** в YARN.

В UI:
- `http://<MASTER_IP>:9870/dfshealth.html#tab-datanode` — два live nodes;
- `http://<MASTER_IP>:8088/cluster/nodes` — два active nodes.

## Шаг 7. Smoke-тест — WordCount

```powershell
# создаём в HDFS папку и кладём файл
docker exec namenode bash -c "echo 'hello hadoop hello world hadoop' > /tmp/in.txt"
docker exec namenode hdfs dfs -mkdir -p /demo/input
docker exec namenode hdfs dfs -put /tmp/in.txt /demo/input/

# запускаем встроенный пример WordCount на YARN
docker exec resourcemanager `
  hadoop jar /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.3.6.jar `
  wordcount /demo/input /demo/output

# результат
docker exec namenode hdfs dfs -cat /demo/output/part-r-00000
```

Если видишь подсчёт слов — кластер реально работает (HDFS на 2-х
воркерах, MR-job выполнился через YARN).

## Шаг 8. Остановка

Везде:

```powershell
docker compose -f docker-compose.master.yml down       # на мастере
docker compose -f docker-compose.worker.yml down       # на каждом воркере
```

Чтобы дополнительно почистить данные HDFS — добавь `-v`:

```powershell
docker compose -f docker-compose.master.yml down -v
```

## Локальный smoke-тест на одном ноуте

Перед развёртыванием на 3 машины можно убедиться, что образ и конфиги
вообще валидны, на одном ноуте:

```powershell
docker compose -f docker-compose.local.yml up -d --build
# открой http://localhost:9870 и http://localhost:8088
# проверь, что в HDFS подключилось 2 DataNode:
docker exec namenode hdfs dfsadmin -report
# и в YARN — 2 NodeManager:
docker exec resourcemanager yarn node -list -all
# WordCount end-to-end:
docker exec namenode bash -c "echo 'hello hadoop hello world' > /tmp/in.txt \
    && hdfs dfs -mkdir -p /demo/input \
    && hdfs dfs -put -f /tmp/in.txt /demo/input/"
docker exec resourcemanager hadoop jar \
    /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.3.6.jar \
    wordcount /demo/input /demo/output
docker exec namenode hdfs dfs -cat /demo/output/part-r-00000
# уборка
docker compose -f docker-compose.local.yml down -v
```

В local-режиме воркер — это один контейнер на роль worker (DataNode +
NodeManager в одном процессе), чтобы Docker DNS на bridge-сети
однозначно резолвил `worker1`/`worker2` в один IP. На проде эти роли
крутятся в **разных** контейнерах — там конфликта DNS нет, потому что
hostname'ы резолвятся через `extra_hosts` в LAN-IP реальных машин.

## Запуск SimpleApp (LineCount MapReduce)

В репозитории есть учебное MapReduce-приложение **SimpleApp** — считает
количество строк во входном файле. Исходники лежат в `app/SimpleApp/`.

### Быстрый запуск (автоматический)

Скрипт `run-simpleapp.ps1` сам соберёт JAR, положит тестовый файл в HDFS
и запустит задачу на YARN:

```powershell
# На мастер-ноуте (или на единственном ноуте в local-режиме),
# из корня репозитория в PowerShell:
.\scripts\run-simpleapp.ps1
```

На выходе увидишь что-то вроде:

```
Number of lines:	10
```

### Пошаговый запуск (ручной)

#### 1. Сборка JAR

Maven/JDK на ноуте не нужны — сборка идёт внутри Docker-контейнера:

```powershell
.\scripts\build-app.ps1
```

JAR появится в `app/SimpleApp/target/SimpleApp-1.0-SNAPSHOT.jar`.

#### 2. Копирование JAR в контейнер

```powershell
docker cp app/SimpleApp/target/SimpleApp-1.0-SNAPSHOT.jar resourcemanager:/tmp/
```

#### 3. Подготовка входных данных в HDFS

```powershell
# Создаём файл и кладём в HDFS
docker exec namenode bash -c "echo 'строка 1
строка 2
строка 3' > /tmp/input.txt"
docker exec namenode hdfs dfs -mkdir -p /simpleapp/input
docker exec namenode hdfs dfs -put -f /tmp/input.txt /simpleapp/input/
```

#### 4. Запуск MapReduce-задачи

```powershell
docker exec resourcemanager hadoop jar /tmp/SimpleApp-1.0-SNAPSHOT.jar `
    by.bsu.rct.bigdata.LineCountDriverMR /simpleapp/input /simpleapp/output
```

#### 5. Просмотр результата

```powershell
docker exec namenode hdfs dfs -cat /simpleapp/output/part-r-00000
```

> **Примечание:** перед повторным запуском удали выходную директорию:
> `docker exec namenode hdfs dfs -rm -r /simpleapp/output`

### Свой входной файл

Чтобы посчитать строки в своём файле:

```powershell
docker cp my-file.txt namenode:/tmp/my-file.txt
docker exec namenode hdfs dfs -mkdir -p /mydata/input
docker exec namenode hdfs dfs -put /tmp/my-file.txt /mydata/input/
.\scripts\run-simpleapp.ps1 -InputPath /mydata/input -OutputPath /mydata/output
```

## Структура репозитория

```
.
├── Dockerfile               # один образ для всех ролей Hadoop
├── docker-compose.master.yml
├── docker-compose.worker.yml
├── docker-compose.local.yml # all-in-one для теста на 1 машине
├── .env.example             # шаблон конфигурации сети
├── app/
│   └── SimpleApp/           # учебное MapReduce-приложение (LineCount)
│       ├── pom.xml
│       └── src/
├── config/                  # Hadoop конфиги, копируются в /opt/hadoop/etc/hadoop
│   ├── core-site.xml
│   ├── hdfs-site.xml
│   ├── yarn-site.xml
│   ├── mapred-site.xml
│   ├── hadoop-env.sh
│   └── workers
└── scripts/
    ├── entrypoint.sh        # выбирает сервис по $HADOOP_ROLE
    ├── build-app.ps1        # сборка SimpleApp JAR (Maven в Docker) — PowerShell
    ├── build-app.sh         # то же для Linux / Git Bash
    ├── run-simpleapp.ps1    # сборка + загрузка данных + запуск MR job — PowerShell
    └── run-simpleapp.sh     # то же для Linux / Git Bash
```

## Решение проблем

**`MASTER_IP должен быть задан в .env`** — забыл скопировать `.env.example`
в `.env` или указать в нём IP.

**DataNode стартовал, но не появляется в `hdfs dfsadmin -report`** —
значит NameNode не может достучаться до DataNode по hostname `worker1` /
`worker2`. Проверь:
- IP в `.env` совпадают с реальными адресами;
- порты 9866, 9867 не закрыты файрволом на воркере;
- `docker logs datanode` на воркере — нет ли там ошибок резолва имени.

**MR-job висит в `ACCEPTED` и не уходит в `RUNNING`** — у NodeManager не
хватает памяти. Уменьши `yarn.nodemanager.resource.memory-mb` в
`config/yarn-site.xml` под реальное железо или, наоборот, дай Docker
Desktop больше RAM (Settings → Resources).

**NameNode не стартует, ругается на формат** — обычно это после смены
конфигов с уже отформатированной FS. На мастере:

```powershell
docker compose -f docker-compose.master.yml down -v
docker compose -f docker-compose.master.yml up -d --build
```

## Лицензия

Учебный проект. Apache Hadoop распространяется под Apache License 2.0.
