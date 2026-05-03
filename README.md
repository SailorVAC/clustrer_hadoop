# clustrer_hadoop

Hadoop-кластер в Docker на 3 ноутбуках: **1 мастер + 2 воркера**.

Стек: **Hadoop 3.3.6** (HDFS + YARN + MapReduce) на базе **OpenJDK 11**
(`eclipse-temurin:11-jre-jammy`). Контейнеры на разных ноутбуках общаются
друг с другом через bridge-сеть Docker и `extra_hosts`, проброшенные порты
+ обращение по hostname'ам `master`, `worker1`, `worker2`. Никаких
экспериментальных режимов Docker Desktop включать не нужно.

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
docker compose -f docker-compose.local.yml down -v
```

## Структура репозитория

```
.
├── Dockerfile               # один образ для всех ролей Hadoop
├── docker-compose.master.yml
├── docker-compose.worker.yml
├── docker-compose.local.yml # all-in-one для теста на 1 машине
├── .env.example             # шаблон конфигурации сети
├── config/                  # Hadoop конфиги, копируются в /opt/hadoop/etc/hadoop
│   ├── core-site.xml
│   ├── hdfs-site.xml
│   ├── yarn-site.xml
│   ├── mapred-site.xml
│   ├── hadoop-env.sh
│   └── workers
└── scripts/
    └── entrypoint.sh        # выбирает сервис по $HADOOP_ROLE
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
