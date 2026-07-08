# Postgres Pool Remediation Runbook

Step-by-step fix when API pods hold **too many** Postgres connections (e.g. 100–320 per pod).

**Health reference:** [../troubleshooting/POSTGRES-CONNECTION-POOL-HEALTH-DEEP-DIVE.md](../troubleshooting/POSTGRES-CONNECTION-POOL-HEALTH-DEEP-DIVE.md)

---

## When to use this

- Any API pod `total` **> 30** at idle, or **> 40** under load
- Global `used / max_connections` **> 70%**
- Users see random 500s/timeouts while `active` queries look low

---

## Step 1 — Measure (2 min)

**Postgres pod:**

```sql
SELECT
  COUNT(*) AS used,
  (SELECT setting::int FROM pg_settings WHERE name='max_connections') AS max
FROM pg_stat_activity
WHERE datname = current_database();
```

```sql
SELECT client_addr, COUNT(*) AS total
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid()
GROUP BY client_addr ORDER BY total DESC;
```

Save screenshot or numbers.

---

## Step 2 — Emergency relief (5 min)

Rolling restart **all API server pods** (one by one).

Re-run per-client query. Totals should drop sharply (often to single digits per pod).

---

## Step 3 — Set pool limits (ConfigMap)

Add to API environment (`onyx-config` or equivalent):

```yaml
POSTGRES_API_SERVER_POOL_SIZE: "15"
POSTGRES_API_SERVER_POOL_OVERFLOW: "5"
POSTGRES_API_SERVER_READ_ONLY_POOL_SIZE: "8"
POSTGRES_API_SERVER_READ_ONLY_POOL_OVERFLOW: "2"
```

**Math (3 API replicas):**

- ~20 max per pool × pools per pod (verify in app)
- aim API tier **< 60–80** total before workers

Apply via GitOps/ArgoCD or cluster admin.

---

## Step 4 — Restart API again

Pool env is read at process start. Rolling restart required.

Verify on **each** API pod:

```bash
printenv | grep POSTGRES_API_SERVER_POOL
```

---

## Step 5 — Validate (15–30 min)

Run [5-USER-CONCURRENT-UPLOAD-TEST-SCENARIO.md](../troubleshooting/5-USER-CONCURRENT-UPLOAD-TEST-SCENARIO.md).

**Pass:**

- each API IP peak **≤ 25–30** total
- global used **< 70%** max
- no pod at 100+

**Fail:**

- counts climb above 40 with light traffic → suspect leak; open app ticket
- only global max issue → review `max_connections` after pools capped

---

## Step 6 — Optional hardening

1. Raise Postgres `max_connections` only if pools are capped and still tight
2. Add **PgBouncer** (transaction pooling) for long-term
3. Add alerts from [POSTGRES-CONNECTION-POOL-HEALTH-DEEP-DIVE.md](../troubleshooting/POSTGRES-CONNECTION-POOL-HEALTH-DEEP-DIVE.md) Part 9

---

## Do not

- Set `POOL_SIZE=80` on 3 replicas without calculating total
- Only increase `max_connections` while pools are unbounded
- Ignore uneven pod totals (one pod 10× others)
