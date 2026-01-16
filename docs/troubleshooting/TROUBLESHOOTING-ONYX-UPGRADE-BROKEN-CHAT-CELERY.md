# Troubleshooting: Onyx upgrade broke chat + celery workers (OpenShift, no CLI)

This guide targets the exact failure pattern you showed:

- `psycopg2.errors.UndefinedColumn: column search_settings.background_reindex_enabled does not exist`
- `AttributeError: TOOL_CALL_RESPONSE`

These almost always mean you have an **upgrade mismatch**:

1) **Database migrations not applied** (code expects new DB columns)  
2) **Mixed / inconsistent backend code inside the image** (some Python modules updated, others not)

You said you **don’t have `oc/kubectl` terminal access**, but you *can* exec into pods. This guide is written for that.

---

## Step 0 — Understand what’s breaking

### Error A: `search_settings.background_reindex_enabled does not exist`

This is a pure Postgres schema mismatch:
- New Onyx code queries `search_settings.background_reindex_enabled`
- Your Postgres table `search_settings` does not have that column yet

Impact:
- API server can fail during startup or during requests
- Celery workers (especially user-file-processing) can fail because they read `search_settings` to decide the active index

### Error B: `AttributeError: TOOL_CALL_RESPONSE`

This points to **inconsistent code** in the running container:

- some file references `MessageType.TOOL_CALL_RESPONSE`
- but the `MessageType` enum that got imported at runtime does not have that member

Most common cause in production:
- building a custom image that “copies a few files” onto another image (partial overlay)
- or running different image tags across api / celery pods

---

## Step 1 — Verify DB is missing the column (Postgres pod)

In the **Postgres pod** (you can use the OpenShift UI “Terminal” tab):

> Important: `psql -U postgres` connects you as the `postgres` user, but it does **not**
> guarantee you are connected to the **same database** Onyx uses. You must confirm the DB name.

```sql
\d search_settings
```

If you do **not** see `background_reindex_enabled`, you must apply migrations.

---

## Step 1.1 — Make sure you’re checking the *correct* Postgres database

### How to see “which database am I connected to?” in `psql`

Inside `psql`:

```sql
SELECT current_database(), current_schema();
SHOW search_path;
```

You can also run:

```sql
\conninfo
```

### How to know which database Onyx uses (without `oc`)

In the **api-server pod** terminal, print the Postgres env vars:

```bash
echo "HOST=$POSTGRES_HOST PORT=$POSTGRES_PORT DB=$POSTGRES_DB USER=$POSTGRES_USER"
```

Then, in the **Postgres pod**, connect to the same DB:

```bash
psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
```

If you don’t have those env vars inside the Postgres pod, just type them manually based on the api-server output:

```bash
psql -U <POSTGRES_USER> -d <POSTGRES_DB>
```

> If you connect without `-d`, `psql` often defaults to a DB named the same as the user (e.g. `postgres`),
> which is commonly **not** the application DB.

---

## Step 2 — Apply DB migrations (without `oc`)

### Option A (preferred): run migrations in the **api-server pod**

Open a shell inside the **api-server** pod and run:

```bash
alembic upgrade head
```

Notes:
- Run this **once** (don’t run concurrently in multiple pods).
- If it fails, copy/paste the full error output.

### Option B: if api-server doesn’t have alembic available

Some deployments run migrations from an initContainer only.
If `alembic` is not found inside the api container:

```bash
which alembic || python -m alembic --help
```

- If both fail, you’re likely not in the backend container image you think you are.
  Check the pod’s **Image** in the OpenShift UI (Details tab).

---

## Step 3 — Confirm migrations actually applied

Back in Postgres (`psql`):

```sql
\d search_settings
```

You should now see the missing column(s).

If Onyx uses Alembic normally, you can also check:

```sql
SELECT * FROM alembic_version;
```

### If migrations “succeeded” but you still don’t see the column

This usually means you ran Alembic against a **different DB/schema** than the one you’re inspecting.
Use this query to search for the column across *all* schemas:

```sql
SELECT table_schema, table_name, column_name
FROM information_schema.columns
WHERE table_name = 'search_settings'
  AND column_name = 'background_reindex_enabled';
```

- If it returns a row: run `\d <schema>.search_settings` for that schema.
- If it returns 0 rows: Alembic didn’t apply this migration to the DB it connected to.

---

## Step 4 — Fix the `TOOL_CALL_RESPONSE` problem (image consistency)

This is not a DB problem. It’s a **code consistency** problem.

### 4.0 Quick check: confirm the container’s code paths are consistent (helps detect “partial overlay” images)

Inside the **api-server pod**, run:

```bash
python -c 'import onyx; import inspect, onyx.db.search_settings as s; print("onyx package:", onyx.__file__); print("search_settings:", s.__file__)'
```

If these paths look unexpected (e.g., a mix of multiple roots or a custom overlay directory), your image likely contains a **partial file copy** and is not a clean, single-version build.

### 4.1 Check whether the enum exists in *this* running container

Inside the **api-server pod**:

```bash
python -c 'from onyx.configs.constants import MessageType; print([m.name for m in MessageType])'
```

Expected in newer releases:
- the list should include `TOOL_CALL_RESPONSE` (and other tool-related values)

If it’s missing but the stack trace shows code referencing it, then your image is inconsistent.

### 4.2 Confirm all backend-related pods are running the **same image tag**

In OpenShift UI:

- go to **Workloads → Deployments**
- check these deployments and confirm they use the **same image** (same tag):
  - `api-server`
  - `celery-beat`
  - all `celery-worker-*` (especially `celery-worker-user-file-processing`)

If they differ, update them so they match.

### 4.3 If you built a custom backend image by copying files

Avoid “partial file copy” images in production.
Instead:

- build from a single git tag/commit of `onyx-dot-app/onyx` (everything consistent), or
- use the official release images for that version

This is the only reliable way to eliminate enum/class mismatches.

---

## Step 5 — Restart pods (so they reload code + new DB schema)

After migrations + image alignment:

In OpenShift UI:

- **Workloads → Deployments → (select deployment) → Actions → Restart rollout**

Restart at least:
- `api-server`
- `celery-worker-user-file-processing`
- `celery-beat`

Then watch the logs again.

---

## Quick checklist (copy/paste into a ticket)

- [ ] Postgres `search_settings` has `background_reindex_enabled`
- [ ] `alembic upgrade head` succeeds
- [ ] `python -c ... MessageType` shows `TOOL_CALL_RESPONSE`
- [ ] api-server + all celery workers run the exact same image tag
- [ ] restarted rollouts for api-server + celery workers + celery-beat


