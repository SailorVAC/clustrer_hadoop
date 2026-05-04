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
3. [Быстрый старт](#быстрый-старт)
   - [Шаг 1. Клонирование](#шаг-1-клонирование-репозитория)
   - [Шаг 2. IP-адреса](#шаг-2-узнать-ip-всех-3-ноутбуков)
   - [Шаг 3. Файл .env](#шаг-3-создать-env-на-каждом-ноуте)
   - [Шаг 4. Запуск мастера](#шаг-4-запуск-мастера)
   - [Шаг 5. Запуск воркеров](#шаг-5-запуск-воркеров)
   - [Шаг 6. Проверка кластера](#шаг-6-проверка-кластера)
4. [Запуск SimpleApp (LineCount)](#запуск-simpleapp-linecount)
   - [Автоматический запуск](#автоматический-запуск)
   - [Ручной запуск (пошагово)](#ручной-запуск-пошагово)
   - [Свой входной файл](#свой-входной-файл)
5. [Локальный тест на одном ноуте](#локальный-тест-на-одном-ноуте)
6. [Остановка кластера](#остановка-кластера)
7. [Веб-интерфейсы](#веб-интерфейсы)
8. [Структура проекта](#структура-проекта)
9. [Решение проблем](#решение-проблем)

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

## Быстрый старт

### Шаг 1. Клонирование репозитория

На **каждом** из 3 ноутбуков откройте PowerShell:

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
    /user/demo/input /user/demo/output
```

> **Важно:** имя main-класса указывать **не нужно** — оно прописано в манифесте JAR.

Map- и reduce-задачи распределяются по NodeManager'ам на разных воркерах — полноценное распределённое выполнение.

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

В multi-host Docker-кластере каждый ноутбук имеет свою Docker bridge-сеть с
внутренними IP (172.18.x.x). Контейнеры на разных ноутах не видят друг друга
по этим IP.

Решение реализовано на уровне `entrypoint.sh`: при старте контейнеров DataNode и
NodeManager скрипт удаляет из `/etc/hosts` запись Docker bridge IP для hostname
контейнера, оставляя только запись `extra_hosts` с LAN IP. Благодаря этому
Java-сервисы (`InetAddress.getLocalHost()`) рекламируют LAN IP ноутбука, а не
внутренний Docker IP. Все нужные порты (8041, 9866, 13562, 32000–32001) проброшены
через Docker, поэтому коммуникация между узлами работает через LAN.

Результат: **map- и reduce-задачи выполняются распределённо на разных воркерах**.

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

## Остановка кластера

На каждом ноуте:

```powershell
# На мастере:
docker compose -f docker-compose.master.yml down

# На каждом воркере:
docker compose -f docker-compose.worker.yml down
```

Чтобы также удалить данные HDFS (полный сброс):

```powershell
docker compose -f docker-compose.master.yml down -v    # на мастере
docker compose -f docker-compose.worker.yml down -v    # на воркерах
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
├── Dockerfile                   # Единый образ Hadoop для всех ролей
├── docker-compose.master.yml    # Compose для мастер-ноута
├── docker-compose.worker.yml    # Compose для воркер-ноута
├── docker-compose.local.yml     # All-in-one для теста на 1 машине
├── .env.example                 # Шаблон конфигурации (скопировать в .env)
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
    ├── build-app.ps1            # Сборка JAR через Maven в Docker (PowerShell)
    ├── build-app.sh             # Сборка JAR (Bash)
    ├── run-simpleapp.ps1        # Полный цикл: сборка + запуск MR (PowerShell)
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

Ошибка `java.net.ConnectException: Connection refused` при доступе к `worker1:9866` или `worker2:32001` означает, что Hadoop-сервисы рекламируют Docker bridge IP (172.18.x.x) вместо LAN IP.

**Решение:** пересоберите и перезапустите контейнеры на воркерах — `entrypoint.sh` автоматически исправляет `/etc/hosts`:

```powershell
# На каждом воркере:
docker compose -f docker-compose.worker.yml down
docker compose -f docker-compose.worker.yml up -d --build
```

Если проблема сохраняется, проверьте что порты 9866, 13562, 32000–32001 открыты в файрволе на воркерах.

---

## Лицензия

Учебный проект. Apache Hadoop распространяется под Apache License 2.0.
