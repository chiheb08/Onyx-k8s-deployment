# Postgres Connections per Instance — Monitoring Query

Use this to see **how many DB connections each client (pod/IP) is using** after changing API pool settings (`POSTGRES_API_SERVER_POOL_SIZE`, `POSTGRES_API_SERVER_POOL_OVERFLOW`).

**Where to run:** Postgres pod terminal (`psql`).

---

## Connect

```bash
PGPASSWORD=$POSTGRES_PASSWORD psql -h localhost -U $POSTGRES_USER -d $POSTGRES_DB
```

(Adjust host/user/db if your secret names differ.)

---

## Main query — connections per client

```sql
SELECT
  client_addr,
  COUNT(*) AS total_connections,
  COUNT(*) FILTER (WHERE state = 'active') AS active,
  COUNT(*) FILTER (WHERE state = 'idle') AS idle,
  COUNT(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_tx
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
GROUP BY client_addr
ORDER BY total_connections DESC;
```

### How to read results

| Column | Meaning |
|--------|---------|
| `client_addr` | Usually one Kubernetes pod IP (API or worker) |
| `total_connections` | All connections from that client |
| `active` | Running a query now |
| `idle` | Open connection, waiting in pool |
| `idle_in_tx` | Open transaction not finished (watch for leaks) |

Map `client_addr` to pod: `kubectl get pods -n <namespace> -o wide` and match IPs.

---

## Global usage vs limit

```sql
SELECT
  COUNT(*) AS db_connections_used,
  (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_connections
FROM pg_stat_activity
WHERE datname = current_database();
```

---

## Per API replica math (reminder)

With 3 API replicas and e.g. `POOL_SIZE=20`, `OVERFLOW=10`:

- Max per API pod ≈ **30**
- Max from API tier ≈ **90** (3 × 30), plus Celery/worker connections

Run the main query **during load** (5–10 users) to see real usage per instance.

---

## Repeat during test (optional)

```sql
SELECT
  now() AS ts,
  client_addr,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE state = 'active') AS active
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
GROUP BY client_addr
ORDER BY total DESC;
```

Run every 30 seconds while users chat/upload.
