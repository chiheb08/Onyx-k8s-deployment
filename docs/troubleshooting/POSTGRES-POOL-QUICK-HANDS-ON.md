# Postgres Pool Problem — Super Easy Hands-On (10 Minutes)

If your app feels slow/crashy and uploads hang, do this exact checklist.

No deep theory. Just **check → decide → fix**.

---

## What this detects

- Too many DB connections from API pods
- One API pod hoarding connections
- Whether restart + pool cap fixed it

---

## Step 0 — Open Postgres terminal

```bash
PGPASSWORD=$POSTGRES_PASSWORD psql -h localhost -U $POSTGRES_USER -d $POSTGRES_DB
```

---

## Step 1 — Is DB full?

Run:

```sql
SELECT
  COUNT(*) AS used,
  (SELECT setting::int FROM pg_settings WHERE name='max_connections') AS max
FROM pg_stat_activity
WHERE datname = current_database();
```

### Read it like this

- `used/max < 70%` → OK for now
- `used/max 70–85%` → warning
- `used/max > 85%` → danger (likely user impact)

---

## Step 2 — Which pod is opening too many?

Run:

```sql
SELECT
  client_addr,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE state='active') AS active
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
GROUP BY client_addr
ORDER BY total DESC;
```

### Healthy target (3 API pods)

- each API row usually around **5–25**
- during short peak maybe **up to ~30**
- roughly balanced across 3 API pods

### Bad target

- one pod at **100+** (or 320 like your case)
- very uneven values (example: 320 / 108 / 40)

---

## Step 3 — Quick meaning of `active=0`

If `active=0` but `total` is huge, it means:

- connections are mostly **idle**
- still consuming DB slots
- app can still fail when new traffic arrives

So huge idle counts are still a real problem.

---

## Step 4 — Immediate fix (safe)

1. Rolling restart API pods (one by one)
2. Re-run Step 2 query

Expected right after restart:

- per API pod totals drop a lot
- if still very high quickly, config/leak issue remains

---

## Step 5 — Permanent fix (set pool caps)

In API config/env, set:

```yaml
POSTGRES_API_SERVER_POOL_SIZE: "15"
POSTGRES_API_SERVER_POOL_OVERFLOW: "5"
POSTGRES_API_SERVER_READ_ONLY_POOL_SIZE: "8"
POSTGRES_API_SERVER_READ_ONLY_POOL_OVERFLOW: "2"
```

Then restart API pods again.

---

## Step 6 — Verify env really loaded

Inside each API pod:

```bash
printenv | grep POSTGRES_API_SERVER_POOL
```

If missing, your config change was not applied.

---

## Step 7 — 5-user quick test (15 min)

- Ask 5 users to upload files at same time
- While they upload, run Step 1 and Step 2 every 30 seconds

### Pass

- each API pod mostly <= 25–30
- no pod goes 100+
- `used/max` stays under ~70%
- user uploads complete normally

### Fail

- one pod climbs 40, 80, 100+ and keeps growing
- `used/max` goes >85%
- uploads time out/fail

---

## One-screen decision table

| What you see | What it means | What to do |
|--------------|----------------|------------|
| `used/max > 85%` | DB near full | restart API + cap pools |
| one API IP very high | pod hoarding/leak/imbalance | cap pools + restart + re-test |
| all API IPs low, app slow | not DB pool issue | check Redis/Celery/indexing |
| high `active` constantly | DB/query pressure | check slow queries/CPU |

---

## Your case (from your screenshots)

- API rows: **320 / 108 / 40**
- `active`: **0**
- long idle age (~47 min)

Verdict: **unhealthy** (too many idle connections held open).

---

## If you want deeper docs

- Detailed interpretation: `POSTGRES-CONNECTION-POOL-HEALTH-DEEP-DIVE.md`
- Full remediation runbook: `../reference/POSTGRES-POOL-REMEDIATION-RUNBOOK.md`
- 5-user test script: `5-USER-CONCURRENT-UPLOAD-TEST-SCENARIO.md`
