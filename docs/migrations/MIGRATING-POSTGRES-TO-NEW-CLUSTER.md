# Migrating Onyx Postgres to a new cluster (OpenShift/Kubernetes)

This is a practical runbook for moving the **Onyx Postgres database** from an **old cluster** (Postgres runs as a pod) to a **new cluster** where you’re redeploying Onyx.

It is written to work even when you **don’t have `oc/kubectl` CLI access** and can only exec into pods via the OpenShift UI.

---

## What Onyx stores in Postgres (why this matters)

Onyx uses Postgres as the **system of record** for:

- users / auth metadata
- connectors + credentials
- projects + user files
- chat sessions + messages + feedback
- search settings (e.g. `search_settings`), migrations (`alembic_version`), etc.

Vespa is a **search index**; it can be rebuilt. Postgres is the **source of truth** you want to migrate.

---

## Migration strategy options

### Option A (recommended): logical backup + restore (pg_dump/pg_restore)

Best for:
- simplest, most reliable, most common
- moving between clusters

Trade-offs:
- requires a **maintenance window** (short downtime) unless you build a more complex “dual write / replication” plan

### Option B: streaming replication / base backup

Best for:
- near-zero downtime migrations

Trade-offs:
- more complex (WAL/replication, storage/layout constraints)
- typically not worth it unless you have strict downtime requirements

This doc focuses on **Option A**.

---

## Before you start: prerequisites checklist

### 1) Postgres version compatibility

Check the major version (old and new). In the **old Postgres pod**:

```bash
psql -U postgres -c 'SHOW server_version;'
```

Rule of thumb:
- restoring a dump into the **same major version** is easiest
- restoring into a **newer major** usually works (logical restore)

### 2) Know which DB Onyx uses

In the **api-server pod** in the old cluster:

```bash
echo "POSTGRES_HOST=$POSTGRES_HOST POSTGRES_PORT=$POSTGRES_PORT POSTGRES_DB=$POSTGRES_DB POSTGRES_USER=$POSTGRES_USER"
```

Use `POSTGRES_DB` for dump/restore (don’t assume it’s `postgres`).

### 3) Decide where the dump file will live

Because you’re moving between clusters, you need a bridge. Common choices:

- **S3/MinIO/Object Storage** reachable from both clusters (recommended)
- a shared NFS volume mounted in both clusters
- download the dump locally from the OpenShift UI (only works for small dumps and depends on your platform)

---

## Step-by-step plan (Option A): dump → transfer → restore

### Step 0 — Put Onyx into “maintenance mode” (freeze writes)

You want a consistent snapshot. The simplest is to stop writers.

In the **old cluster**, scale down (or stop) these deployments:

- `api-server`
- `celery-beat`
- all `celery-worker-*`

Keep **Postgres** running.

Why:
- prevents new chat messages, connector sync, file indexing changes during the dump

> If you cannot scale down via CLI, do it in OpenShift UI: Workloads → Deployments → set Replicas to 0.

### Step 1 — Create a logical backup in the old cluster

Exec into the **old Postgres pod**.

#### 1.1 Create a compressed custom-format dump (recommended)

```bash
export DB="<POSTGRES_DB>"
export USER="<POSTGRES_USER>"
export OUT="/tmp/onyx.dump"

pg_dump -U "$USER" -d "$DB" -Fc -Z 6 -f "$OUT"
ls -lh "$OUT"
```

Notes:
- `-Fc` = custom format (best for `pg_restore`)
- `-Z 6` = compression level

#### 1.2 (Optional) Also dump roles if you manage roles manually

If you rely on custom DB roles (not always necessary in single-container setups):

```bash
pg_dumpall -U "$USER" --globals-only > /tmp/onyx-globals.sql
```

### Step 2 — Transfer the dump to the new cluster

Pick one method.

#### Method A (recommended): upload to object storage from inside the pod

If your Postgres pod has `awscli`/`curl`, upload to S3/MinIO.

Example (S3-compatible endpoint):

```bash
# Example only: adjust to your object storage
aws s3 cp /tmp/onyx.dump s3://<bucket>/onyx/onyx.dump
aws s3 cp /tmp/onyx-globals.sql s3://<bucket>/onyx/onyx-globals.sql
```

If `aws` isn’t available, you can sometimes use `curl` to a presigned URL.

#### Method B: download via OpenShift UI

Some OpenShift setups allow downloading files from the terminal session or via “Copy/Download” features.
If your dump is large, prefer object storage instead.

### Step 3 — Prepare the new Postgres in the new cluster

Deploy Postgres in the new cluster (StatefulSet or operator). Ensure:

- persistent volume is sized appropriately
- credentials/secrets are ready
- database is created (or you will create it now)

Exec into the **new Postgres pod**.

#### 3.1 Create the target database (if missing)

```bash
createdb -U postgres <POSTGRES_DB>
```

### Step 4 — Restore into the new Postgres

#### 4.1 Bring the dump file into the new cluster

Download from object storage inside the **new Postgres pod**:

```bash
aws s3 cp s3://<bucket>/onyx/onyx.dump /tmp/onyx.dump
aws s3 cp s3://<bucket>/onyx/onyx-globals.sql /tmp/onyx-globals.sql
```

#### 4.2 Restore globals (optional)

```bash
psql -U postgres -f /tmp/onyx-globals.sql
```

#### 4.3 Restore the database

```bash
pg_restore -U <POSTGRES_USER> -d <POSTGRES_DB> --clean --if-exists /tmp/onyx.dump
```

Notes:
- `--clean --if-exists` helps when restoring into a DB that already has objects
- if role ownership differs between clusters, consider adding:
  - `--no-owner --no-privileges`

---

## Post-restore validation (very important)

In the **new Postgres**:

### 1) Sanity: how many tables and is alembic present?

```sql
\\dt
SELECT * FROM alembic_version;
```

### 2) Verify key tables have data

```sql
SELECT COUNT(*) FROM \"user\";
SELECT COUNT(*) FROM chat_session;
SELECT COUNT(*) FROM chat_message;
SELECT COUNT(*) FROM search_settings;
```

### 3) Check schema list (multi-tenant)

```sql
\\dn
```

If you use multi-tenancy, you may have multiple tenant schemas (`tenant_<id>`).

---

## Bringing up Onyx in the new cluster

### Step 1 — Point Onyx to the new Postgres

Update the new cluster’s config/secrets (your repo uses `manifests/05-configmap.yaml` and `postgresql-secret`):

- `POSTGRES_HOST`
- `POSTGRES_PORT`
- `POSTGRES_DB`
- `POSTGRES_USER` / `POSTGRES_PASSWORD` (Secret)

### Step 2 — Run migrations in the new cluster (once)

After restore, run migrations using the **same api-server image tag** you deploy:

```bash
alembic upgrade head
```

### Step 3 — Restart/scale up workloads

Scale up:

- `api-server`
- `celery-beat`
- celery workers

---

## Vespa note (do you migrate it?)

Usually: **no**.

Vespa is an index and can be rebuilt by re-indexing. After you restore Postgres and bring up Onyx, you may need to:

- re-run connectors indexing
- re-index user files if needed

---

## Common failure modes + fixes

### “pg_restore fails with permission/role errors”

Restore with:

```bash
pg_restore -U <POSTGRES_USER> -d <POSTGRES_DB> --no-owner --no-privileges /tmp/onyx.dump
```

### “Onyx starts but behaves strangely”

Make sure:
- all backend pods use the same Onyx version
- you ran `alembic upgrade head` after restore

### “We can’t transfer large files between clusters”

Use object storage (S3/MinIO) with a bucket accessible from both clusters.

---

## Recommended “minimal downtime” timeline

- **T-30 min**: confirm versions, secrets, storage, and transfer method
- **T-10 min**: scale down Onyx writers in old cluster
- **T-0**: `pg_dump` in old cluster
- **T+X**: upload dump to object storage
- **T+X**: restore in new cluster
- **T+X**: run `alembic upgrade head` in new cluster
- **T+X**: scale up Onyx in new cluster

