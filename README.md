# 🐘 Hadoop-кластер на 3 машинах

<p align="center">
  <b>Hadoop 3.3.6</b> &nbsp;|&nbsp; <b>Spark 3.5.7</b> &nbsp;|&nbsp; HDFS + YARN + MapReduce &nbsp;|&nbsp; Docker &nbsp;|&nbsp; Windows
</p>

Готовый сценарий поднять распределённый Hadoop+Spark-кластер на **трёх Windows-машинах** через Docker. Один и тот же скрипт `start.bat` на каждой машине определяет её роль по IP и поднимает нужный набор контейнеров.

---

## Содержание

1. [Архитектура](#архитектура)
2. [Требования](#требования)
3. [Быстрый старт (3 шага)](#быстрый-старт-3-шага)
4. [Остановка кластера](#остановка-кластера)
5. [Настройка ролей](#настройка-ролей)
6. [Генератор конфигов (setup-cluster)](#генератор-конфигов-setup-cluster)
7. [Локальный тест на одной машине](#локальный-тест-на-одной-машине)
8. [Веб-интерфейсы](#веб-интерфейсы)
9. [Структура проекта](#структура-проекта)
10. [Решение проблем](#решение-проблем)

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
│  + Spark 3.5.7 (client)      │     │  + Spark 3.5.7  │     │  + Spark 3.5.7  │
│  для spark-submit на YARN    │     │  (executors)    │     │  (executors)    │
└──────────┬──────────────────┘     └────────┬─────────┘     └────────┬─────────┘
           │         LAN (192.168.x.x)       │                        │
           └─────────────────────────────────┴────────────────────────┘
```

| Ноут        | Контейнеры                                                  |
|-------------|-------------------------------------------------------------|
| **master**  | NameNode, SecondaryNameNode, ResourceManager, HistoryServer |
| **worker1** | DataNode, NodeManager                                       |
| **worker2** | DataNode, NodeManager                                       |

Spark поставлен в тот же образ и через `spark-submit --master yarn` отправляет задания в общий YARN.

Распределение ролей **гибкое** — любую роль можно вынести на отдельную машину или объединить (см. [Настройка ролей](#настройка-ролей)).

---

## Требования

| Что | На master | На worker1/worker2 |
|-----|-----------|--------------------|
| ОС  | Windows 10/11 + Docker Desktop с WSL2 | Windows 10/11 + Docker Desktop с WSL2 |
| RAM | ≥ 6 ГБ свободной | ≥ 4 ГБ свободной |
| Диск | ≥ 10 ГБ | ≥ 5 ГБ |
| Сеть | Все 3 ноута в одной LAN, `ping IP_другого_ноута` проходит | — |

**Открыть порты в Windows Firewall** (на каждой машине):

| Машина              | Порты                                          |
|---------------------|-------------------------------------------------|
| **master**          | 9000, 9870, 9868, 8020, 8030, 8031, 8032, 8033, 8088, 19888 |
| **worker1/worker2** | 9864, 9866, 9867, 8040–8042, 13562, 32000–32001 |

> **Совет:** на время работы можно разрешить весь трафик от подсети машин:
> Windows Defender → Advanced settings → Inbound rules → New rule → Custom → Remote IPs.

---

## Быстрый старт (3 шага)

### Шаг 1. Клонирование

На **каждой** машине:

```powershell
git clone https://github.com/SailorVAC/clustrer_hadoop.git
cd clustrer_hadoop
```

### Шаг 2. Конфигурация

На **одной** машине создайте `cluster.conf`:

```powershell
copy cluster.conf.example cluster.conf
notepad cluster.conf
```

Впишите реальные IP ваших машин (`ipconfig`):

```ini
192.168.1.10  namenode,secondarynamenode,resourcemanager,historyserver
192.168.1.11  datanode
192.168.1.12  datanode
```

Роли можно распределять гибко (подробнее — [Настройка ролей](#настройка-ролей)).

Скопируйте `cluster.conf` на **все** остальные машины (через USB, по сети, или просто создайте одинаковый файл).

### Шаг 3. Запуск

На **каждой** машине — один и тот же скрипт:

```powershell
start.bat
```

Скрипт **автоматически определяет** какая это машина по IP, генерирует нужный `docker-compose.generated.yml` и запускает контейнеры. Первый запуск долгий — собирается образ (~2 ГБ, в нём Hadoop + Spark).

**Порядок:** сначала мастер (NameNode), потом воркеры. Но даже если запустить одновременно — воркеры подождут мастера автоматически.

**Проверка** (на мастере, через ~30 сек после запуска):

```powershell
docker exec namenode hdfs dfsadmin -report
docker exec resourcemanager yarn node -list
```

В отчёте должно быть 2 живых DataNode и 2 active NodeManager.

**Кластер готов.**

---

## Остановка кластера

На каждой машине:

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

Скрипт читает `cluster.conf` (или спрашивает интерактивно, если файла нет) и для каждой машины кладёт в `generated/` пару файлов: `<label>.yml` (docker-compose) и `<label>.env`. На целевой машине достаточно скопировать их в корень репо и запустить `docker compose up -d --build`.

---

## Локальный тест на одной машине

Перед развёртыванием на 3 машины можно убедиться, что образ и конфиги работают, запустив всё на одной машине. В `cluster.conf` укажите один и тот же IP (или `127.0.0.1`) для всех ролей, например:

```ini
127.0.0.1  namenode,secondarynamenode,resourcemanager,historyserver
127.0.0.1  datanode worker1
127.0.0.1  datanode worker2
```

Затем:

```powershell
start.bat

# Проверка: должно быть 2 DataNode и 2 NodeManager
docker exec namenode hdfs dfsadmin -report
docker exec resourcemanager yarn node -list -all

# Уборка
stop.bat -v
```

Несколько воркеров на одной машине различаются именами (`worker1`/`worker2`); скрипт автоматически смещает порты DataNode, чтобы не было конфликтов.

---

## Веб-интерфейсы

| URL | Описание |
|-----|----------|
| `http://<MASTER_IP>:9870`  | **NameNode** — состояние HDFS, DataNode'ы, файловая система |
| `http://<MASTER_IP>:8088`  | **ResourceManager** — YARN, запущенные приложения, NodeManager'ы |
| `http://<MASTER_IP>:19888` | **JobHistory** — история завершённых MapReduce-задач |
| `http://<MASTER_IP>:9868`  | **SecondaryNameNode** |
| `http://<WORKER_IP>:9864`  | **DataNode** на воркере |
| `http://<WORKER_IP>:8042`  | **NodeManager** на воркере |

---

## Структура проекта

```
clustrer_hadoop/
├── start.bat                    # Запуск кластера (на каждой машине)
├── stop.bat                     # Остановка кластера
├── cluster.conf.example         # Шаблон конфигурации → скопировать в cluster.conf
├── Dockerfile                   # Единый образ Hadoop + Spark для всех ролей
│
├── config/                      # Конфиги Hadoop/Spark, копируются в образ
│   ├── core-site.xml
│   ├── hdfs-site.xml
│   ├── yarn-site.xml
│   ├── mapred-site.xml
│   ├── hadoop-env.sh
│   ├── workers
│   └── spark-defaults.conf      # Spark смотрит на YARN + общие лимиты
│
└── scripts/
    ├── entrypoint.sh            # Стартовый скрипт контейнера (выбор роли)
    ├── start.ps1                # Логика запуска (вызывается из start.bat)
    ├── stop.ps1                 # Логика остановки
    └── setup-cluster.{ps1,sh}   # Генератор compose/.env для всех машин
```

Сгенерированные при запуске артефакты (`docker-compose.generated.yml`, `.env`, `generated/`) добавлены в `.gitignore`.

---

## Решение проблем
### Единственный момент со Sparkом: при запуске задачи он требует наличия папки spark-logs в корне hdfs
### поэтому если вылетает с exceptionом её стоит создать.


### ===============================================
`start.bat` не нашёл `cluster.conf`. Скопируйте его из шаблона и впишите IP:

```powershell
copy cluster.conf.example cluster.conf
notepad cluster.conf
```


### DataNode не появляется в `hdfs dfsadmin -report`

NameNode не может подключиться к DataNode по hostname `worker1` / `worker2`. Проверьте:

1. IP в `cluster.conf` совпадают с реальными (`ipconfig` на каждой машине).
2. Порты 9866, 9867 не заблокированы файрволом на воркере.
3. Логи DataNode: `docker logs datanode` — нет ли ошибок подключения.

### MR-задача висит в ACCEPTED

У NodeManager не хватает памяти. Варианты:

- Уменьшить `yarn.nodemanager.resource.memory-mb` в `config/yarn-site.xml`.
- Дать Docker Desktop больше RAM: Settings → Resources.

### NameNode не стартует (ошибка формата)

Обычно после смены конфигов с уже отформатированной FS. Полный сброс с удалением томов:

```powershell
stop.bat -v
start.bat
```

### Не открываются файлы в NameNode Web UI

Браузер получает ошибку вида `Failed to load http://worker2:9874/...`. Это нормальное поведение — HDFS перенаправляет на hostname DataNode, который браузер на вашей машине не может разрешить.

**Решение 1** — добавить записи в `C:\Windows\System32\drivers\etc\hosts`:
```
192.168.1.11  worker1
192.168.1.12  worker2
```

**Решение 2** — просматривать файлы через командную строку:
```powershell
docker exec namenode hdfs dfs -cat /path/to/file
```

### Connection refused при обращении к DataNode (`172.18.0.1:9866` и т.п.)

HDFS-клиент пытается достучаться по Docker bridge IP вместо LAN. Решения:

1. Передавайте `-Ddfs.client.use.datanode.hostname=true` в свои `hadoop`/`spark` команды (значение по умолчанию в конфиге уже выставлено, но некоторые клиенты его перетирают).
2. Пересоберите контейнеры на всех ноутах, чтобы подтянулись актуальные конфиги: `stop.bat` и `start.bat`.
3. Убедитесь, что в `cluster.conf` корректные LAN IP, а порты воркеров (9866, 13562, 32000–32001) открыты в файрволе.

---
