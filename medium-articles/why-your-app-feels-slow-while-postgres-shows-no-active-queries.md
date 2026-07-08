# Why Your App Feels Slow While Postgres Shows 0 Active Queries

*A production deep dive into the most confusing database incident pattern: everything is “idle,” but users still suffer.*

There is a moment in incident response that breaks many teams.

You run a query to inspect Postgres connections.  
You see this:

- `active = 0`
- many connections in `idle`
- lots of last query values like `ROLLBACK;` and `COMMIT;`

Then a teammate says:  
**“If nothing is active, database is fine. Let’s check another service.”**

And that is exactly how incidents get longer.

This article is a practical, no-vendor, production field report. We will break down:

1. What this incident looks like in real numbers
2. Why `active=0` can still mean a serious outage risk
3. How connection pools multiply across replicas
4. How to diagnose root cause in minutes
5. How to fix it safely
6. How to keep it fixed

No advanced theory required. Just the behavior that appears in real clusters.

---

## The Incident Snapshot (Realistic Example)

A team runs an API with 3 replicas on Kubernetes/OpenShift.  
Postgres has `max_connections = 500`.

During business hours, users report:

- uploads feel slow
- random timeouts
- occasional failures during spikes

The database snapshot shows:

- global connections: `393 / 500` (79% used)
- API pod A: `120` connections
- API pod B: `120` connections
- API pod C: `120` connections
- all three mostly `idle`
- `active=0` at inspection moment
- last queries are mostly `ROLLBACK;` (some `COMMIT;`)
- one connection idle for more than 17 hours

At first glance, this looks contradictory:

- “No active queries”
- “But app is slow”

It is not contradictory. It is a classic connection capacity incident.

---

## The One Idea You Must Remember

**Postgres availability is not only about running queries.  
It is also about free connection slots.**

Think of Postgres like a hotel with 500 rooms:

- `active query` = guest currently talking at reception
- `idle connection` = guest still occupying a room quietly

If 393 rooms are occupied by idle guests, the hotel still has only 107 rooms left for everyone else.  
A sudden group arrival causes “no room” problems even if the lobby looks calm.

That is exactly what happens with oversized connection pools.

---

## Why This Happens: Pool Math Across Replicas

Many teams tune one pod and forget cluster multiplication.

If one API process can hold many pooled connections, then:

```text
Total potential connections = per-pod pool capacity × number of pods
```

Now add:

- read/write pools
- background workers
- scheduled jobs
- admin scripts

Your “safe” per-process number can become unsafe cluster-wide.

### Example

If one API pod reaches ~120 pooled connections and you have 3 replicas:

```text
3 × 120 = 360 API connections
```

With workers and other services, global usage can quickly sit around 393/500 all day.  
You have created a fragile system where tiny traffic bursts trigger pain.

---

## Why `ROLLBACK` Appears Everywhere (and Why It Confuses People)

In pooled DB clients, each request often:

1. checks out a connection
2. starts a transaction
3. does work (or does nothing if read path exits early)
4. ends with `COMMIT` or `ROLLBACK`
5. returns connection to pool

So seeing many idle connections whose “last query” is `ROLLBACK` is common.

That line alone is not the bug.

The real signal is:

- very high idle connection count
- long idle age
- connection totals near max

So the question is not “why rollback?”  
The question is “why are hundreds of connections still reserved?”

---

## Why The App Feels Slow Even When DB Looks Quiet

This incident hits latency in indirect ways:

1. New requests wait for available DB connection from pool
2. Some requests time out at gateway/client before backend finishes
3. Retries create more pressure
4. Worker tasks queue up
5. User sees random slowness and inconsistent behavior

You do not need slow SQL to feel slow UX.  
You only need connection scarcity under concurrency.

---

## Fast Triage: 3 Queries That Tell the Truth

Use these in production during incident triage.

### 1) Global pressure

```sql
SELECT
  COUNT(*) AS used,
  (SELECT setting::int FROM pg_settings WHERE name='max_connections') AS max
FROM pg_stat_activity
WHERE datname = current_database();
```

Read:

- `<70%` usually comfortable
- `70-85%` warning
- `>85%` danger zone

### 2) Who is consuming slots

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

Read:

- one IP too high = imbalance/routing issue
- all API IPs equally high = pool config issue replicated evenly

### 3) Idle age and wait profile

```sql
SELECT
  pid,
  client_addr,
  state,
  wait_event_type,
  wait_event,
  LEFT(query, 80) AS query_preview,
  now() - state_change AS time_in_state
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
  AND client_addr = '<one_api_ip>'
ORDER BY time_in_state DESC
LIMIT 20;
```

Read:

- many `idle` + `ClientRead` + long `time_in_state` = over-retained idle pool
- very long outliers (hours) = stale/leaky behavior to investigate

---

## Root Cause Patterns (Most Common)

In real systems, one or more of these are usually true:

1. Pool env variables were never set in production (defaults are too high)
2. Variables were set but pods were not restarted, so old values stayed active
3. Multiple DB engines/pools exist in one process (write + read-only + others)
4. Worker and API both connect aggressively without shared budget
5. Autoscaling increased replicas without reducing per-pod pool caps
6. Connection leak path leaves sessions idle for very long periods

Notice what is missing from this list:

- “Postgres is slow”
- “Need bigger CPU”

Often the first fix is pool governance, not database horsepower.

---

## Remediation That Works in Production

Use conservative caps first. Then measure.

### Step 1: Set explicit pool limits for API

Example:

```yaml
POSTGRES_API_SERVER_POOL_SIZE: "15"
POSTGRES_API_SERVER_POOL_OVERFLOW: "5"
POSTGRES_API_SERVER_READ_ONLY_POOL_SIZE: "8"
POSTGRES_API_SERVER_READ_ONLY_POOL_OVERFLOW: "2"
```

Meaning in plain language:

- keep 15 regular DB lines ready per pod
- allow 5 temporary extra lines during spikes
- separate smaller read-only reserve

### Step 2: Restart API pods

Config changes without restart do nothing for running processes.

### Step 3: Verify env inside running pods

```bash
printenv | grep POSTGRES_API_SERVER_POOL
```

Check every API pod, not only one.

### Step 4: Re-measure with the same SQL

Expect:

- much lower global `used`
- per API pod totals closer to expected cap
- healthier headroom for bursts

### Step 5: Run realistic concurrency test

Do at least a 5-user mixed scenario:

- upload + chat + deletion + search in parallel

If pools are healthy, totals rise and fall, not stay pinned near high numbers.

---

## Sizing Strategy You Can Reuse

Do not choose pool values by guesswork.  
Use a budget.

### 1) Reserve headroom

With `max_connections=500`, reserve at least 30-40% for:

- admin sessions
- migrations
- workers
- operational spikes

Example target budget for API + read paths: ~250-300 max combined, not 450.

### 2) Allocate per component

Split budget among:

- API replicas
- worker replicas
- special jobs

### 3) Back-calculate per-pod limits

If API budget is 120 total and you run 3 replicas:

```text
120 / 3 = 40 max per API pod (combined across its pools)
```

Then tune read/write sub-pools below that combined ceiling.

### 4) Revisit during scaling changes

If HPA changes pod count, per-pod pool caps may need reduction.

---

## Observability: What to Alert On

If you only graph query latency, you will miss this.

Track:

1. `used/max_connections` ratio
2. connections by `client_addr` or `application_name`
3. idle connection count and max idle age
4. API request timeout rate
5. queue depth for worker jobs

Alert suggestions:

- warning at 70%
- critical at 85%
- stale idle connection > 1 hour (tune to your norms)

---

## Common Wrong Fixes

### “Just raise max_connections to 1000”

Temporary relief, often permanent debt.  
You hide bad pooling behavior and increase memory/process overhead.

### “No active queries, so ignore it”

False safety signal. Connection slots can be exhausted while active count is low.

### “Restart Postgres only”

May clear symptom briefly, but the same application pattern will refill quickly.

### “Scale API replicas up”

Without lower per-pod pool caps, scaling out can consume DB slots faster.

---

## A Practical Post-Incident Checklist

After you stabilize production, close the loop:

1. Document current pool values and rationale
2. Add startup log line that prints effective pool config (no secrets)
3. Add runbook query snippets for on-call
4. Add synthetic concurrency test to pre-release checks
5. Define ownership for DB connection budget
6. Review autoscaling + pool settings together each release

Incidents repeat when ownership is unclear.  
Make connection budget a first-class production contract.

---

## Final Takeaway

The hardest production bugs are often not “broken code.”  
They are **correct code running with unsafe defaults at scale**.

If your app is slow and Postgres shows no active queries:

- do not stop investigation
- check connection occupancy, not only activity
- cap pools explicitly
- verify live env in running pods
- measure again under concurrent traffic

You are not chasing ghosts.  
You are managing finite seats in a shared system.

That is what production engineering really is.

---

## Suggested Medium Subtitle

*How idle pooled connections quietly consume your database capacity and create user-facing latency spikes.*

## Suggested Medium Tags

`PostgreSQL` `Kubernetes` `DevOps` `Backend` `Production Engineering`
