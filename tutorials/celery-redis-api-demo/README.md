# Tutorial: API -> Redis Queue -> Celery Worker (Simple Demo)

This is a minimal tutorial project that imitates the Onyx async pattern:

1. API receives request
2. API enqueues a task into Redis (broker)
3. Worker dequeues task and executes it
4. API reads task status/result from Redis backend

It uses:

- FastAPI (`api`)
- Redis (`broker db15`, `result db16`)
- Celery worker (`demo` queue)

> This demo intentionally uses Redis `db15` for broker and `db16` for results (like common Onyx setups), so Redis is started with `--databases 32` in `docker-compose.yml`.

---

## Project layout

```text
tutorials/celery-redis-api-demo/
  docker-compose.yml
  requirements.txt
  app/
    main.py         # FastAPI endpoints
    celery_app.py   # Celery broker/backend config
    tasks.py        # Worker task implementation
```

---

## Step 0: start the demo

From this folder:

```bash
docker compose up -d
docker compose ps
```

Check API health:

```bash
curl http://localhost:8000/health
```

---

## Step 1: enqueue a task (API -> Redis)

```bash
curl -X POST http://localhost:8000/tasks/square \
  -H "Content-Type: application/json" \
  -d '{"value": 12, "delay_seconds": 8}'
```

Example response:

```json
{
  "message": "Task enqueued",
  "task_id": "84f3....",
  "queue": "demo",
  "broker_db": 15,
  "result_backend_db": 16
}
```

Save the `task_id`.

---

## Step 2: watch Redis queue behavior (enqueue/dequeue)

Open a second terminal:

```bash
docker compose exec redis redis-cli -a redispass -n 15 LLEN demo
```

If you run multiple tasks quickly:

```bash
for i in 1 2 3 4 5; do
  curl -s -X POST http://localhost:8000/tasks/square \
    -H "Content-Type: application/json" \
    -d "{\"value\": $i, \"delay_seconds\": 10}" >/dev/null
done

docker compose exec redis redis-cli -a redispass -n 15 LLEN demo
```

You should see queue length increase, then decrease as worker consumes tasks.

Inspect queued raw messages:

```bash
docker compose exec redis redis-cli -a redispass -n 15 LRANGE demo 0 2
```

---

## Step 3: watch worker execution (dequeue + run task)

Open a third terminal:

```bash
docker compose logs -f worker
```

You should see task receive/start/succeed logs.

Also inspect active tasks directly:

```bash
docker compose exec worker celery -A app.celery_app.celery_app inspect active
docker compose exec worker celery -A app.celery_app.celery_app inspect reserved
```

---

## Step 4: query task status/result (API -> backend db16)

Replace `<TASK_ID>`:

```bash
curl http://localhost:8000/tasks/<TASK_ID>
```

States you will see:

- `PENDING` (queued / not finished)
- `SUCCESS` (done, result returned)
- `FAILURE` (exception in worker)

---

## Step 5: verify Redis db separation (important concept)

Broker DB (`15`):

```bash
docker compose exec redis redis-cli -a redispass -n 15 DBSIZE
docker compose exec redis redis-cli -a redispass -n 15 --scan | head
```

Result backend DB (`16`):

```bash
docker compose exec redis redis-cli -a redispass -n 16 DBSIZE
docker compose exec redis redis-cli -a redispass -n 16 --scan | head
```

This mirrors the common Onyx pattern where broker and result backend use different Redis DB numbers.

---

## Step 6: live protocol visibility (advanced)

Watch every Redis command in real time:

```bash
docker compose exec redis redis-cli -a redispass MONITOR
```

Then enqueue tasks again in another terminal and observe:

- `LPUSH`/queue operations
- worker `BRPOP`-like consumption
- result backend writes

---

## Tear down

```bash
docker compose down -v
```

---

## Troubleshooting

### `POST /tasks/square` returns `Internal Server Error`

If API logs contain `DB index is out of range`, Redis was started with too few logical DBs.

Fix:

```bash
docker compose down -v
docker compose up -d
```

(The provided compose file already sets `--databases 32`.)

---

## What this teaches (mapped to Onyx)

- API is the **producer**
- Redis is the **broker**
- Celery worker is the **consumer**
- Queue length (`LLEN`) is backlog
- Logs + `inspect active` prove execution
- Different Redis DBs can explain “empty queue” confusion if you check wrong DB
