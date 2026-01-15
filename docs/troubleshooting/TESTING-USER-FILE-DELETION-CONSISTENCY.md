# Testing user-file deletion consistency (Postgres + Vespa) — step-by-step

This guide gives you a repeatable scenario to verify that when you **delete a user uploaded file**, it:

1) disappears **immediately** from API “file list” endpoints (no UI flicker), and  
2) is eventually removed from **Vespa** and from **Postgres**.

It also explains the backend logic so you know where inconsistencies come from and where to improve.

---

## First: how to access Postgres + Vespa pods (copy/paste)

Set your namespace once:

```bash
export NAMESPACE="<NAMESPACE>"
```

### Postgres: exec + psql

```bash
oc get pods -n "$NAMESPACE" | grep -i postgres
oc exec -n "$NAMESPACE" -it <POSTGRES_POD> -- bash
```

Inside the pod:

```bash
psql -U postgres
```

If `bash` isn’t present, use `sh`:

```bash
oc exec -n "$NAMESPACE" -it <POSTGRES_POD> -- sh
```

### Vespa: exec + curl

```bash
oc get pods -n "$NAMESPACE" | grep -i vespa
oc exec -n "$NAMESPACE" -it <VESPA_POD> -- bash
```

Inside the Vespa pod, you can query the local HTTP API (common):

```bash
curl -s http://localhost:8080/state/v1/health | head
```

---

## Make Postgres output readable (psql “wide table” fix)

When `SELECT *` prints a huge wrapped table, use these psql settings:

### Option 1 (best): Expanded view

```sql
\x on
```

Now each row prints vertically (easy to read for `user_file`). Toggle back:

```sql
\x off
```

### Option 2: Pager with no line-wrapping

```sql
\pset pager on
\setenv PAGER 'less -S'
```

`less -S` disables line wrapping so you can scroll horizontally.

### Best practice: select only the columns you need

Instead of `SELECT *`, use:

```sql
SELECT id, name, status, chunk_count, created_at
FROM user_file
ORDER BY created_at DESC
LIMIT 10;
```

---

## Quick mental model (how deletion works)

In the official Onyx backend (`onyx-dot-app/onyx`):

1) API handler `DELETE /user/projects/file/{file_id}` sets:
   - `user_file.status = DELETING`
   - commits
   - enqueues Celery task `delete_single_user_file`
2) Celery delete task:
   - deletes **Vespa chunks** for the document where `document_id == <user_file_id>`
   - deletes the blob(s) from the file store
   - deletes the **`user_file`** DB row

Important details:

- The `user_file.id` is a UUID.
- During indexing, the document id used in Vespa is set to that same value:
  - `document.id = str(user_file_id)`
  - Vespa field `document_id` is also the `user_file_id`

So when we verify in Vespa, we search by `document_id == '<USER_FILE_UUID>'`.

---

## Scenario A (simplest): upload a file that has **no project/assistant association**

This is the easiest deletion path because the delete endpoint refuses deletion if the file is attached to any project or assistant.

### Step A1 — Upload a file

Do this via UI, or the API endpoint:

- `POST /user/projects/file/upload`
  - `project_id` optional (leave it empty for this test)

After upload, grab the **file id** from the UI (or API response). We’ll call it:

- `USER_FILE_ID=<uuid>`

### Step A2 — Verify it exists in Postgres (`user_file` row)

#### Exec into Postgres

```bash
oc get pods -n <NAMESPACE> | grep -i postgres
oc exec -n <NAMESPACE> -it <POSTGRES_POD> -- bash
```

Connect with `psql` (adjust user/db if needed):

```bash
psql -U postgres
```

Find the newest user files (use this to find the ID if you don’t have it yet):

```sql
SELECT id, name, status, chunk_count, created_at
FROM user_file
ORDER BY created_at DESC
LIMIT 10;
```

Verify the file you uploaded:

```sql
SELECT id, name, status, chunk_count, file_id, created_at
FROM user_file
WHERE id = '<USER_FILE_ID>';
```

Expected:

- `status` is usually `PROCESSING` then becomes `COMPLETED` (or `FAILED` if indexing fails).

### Step A3 — Delete the file

In UI: click delete.

If you want to test the API call directly, it’s:

- `DELETE /user/projects/file/{file_id}`

### Step A4 — Immediately verify “no flicker” in Postgres + lists

Right after you click delete, verify status flips to `DELETING`:

```sql
SELECT id, status, created_at
FROM user_file
WHERE id = '<USER_FILE_ID>';
```

Expected immediately:

- row still exists
- `status = DELETING`

Now, the “no flicker” part depends on list endpoints filtering out `DELETING`.
If any endpoint still returns `DELETING` files, the UI can show the file again temporarily.

Tables to check for associations (should be empty for this scenario):

```sql
SELECT * FROM project__user_file WHERE user_file_id = '<USER_FILE_ID>';
SELECT * FROM persona__user_file WHERE user_file_id = '<USER_FILE_ID>';
```

Expected:

- both return 0 rows

### Step A5 — Verify eventual removal from Postgres

After the delete worker finishes, the `user_file` row should be gone:

```sql
SELECT id, status
FROM user_file
WHERE id = '<USER_FILE_ID>';
```

Expected:

- 0 rows

---

## Scenario B: file is attached to a project (expected “blocked delete”)

This tests the association guardrails.

1) Upload with `project_id=<some project>`, or attach in UI.
2) Try delete:
   - backend should return “has_associations=true” (UI typically shows a warning)
3) Unlink from project:
   - `DELETE /user/projects/{project_id}/files/{file_id}`
4) Delete again.

In Postgres, verify the association row comes and goes:

```sql
SELECT * FROM project__user_file WHERE user_file_id = '<USER_FILE_ID>';
```

---

## Vespa verification (prove the chunks are actually gone)

### Step V1 — Find the active Vespa index name

In Postgres:

```sql
SELECT id, index_name, status
FROM search_settings
ORDER BY id DESC
LIMIT 10;
```

Pick the active/current index. Common default is `danswer_chunk`, but don’t guess—use the DB value.

Set:

- `INDEX_NAME=<index_name>`

### Step V2 — Exec into the Vespa pod and “visit” documents by selection

```bash
oc get pods -n <NAMESPACE> | grep -i vespa
oc exec -n <NAMESPACE> -it <VESPA_POD> -- bash
```

Now query Vespa using **YQL (Vespa Query Language)** from inside the pod.

Preferred: use the built-in Vespa CLI (`vespa query`) inside the container.

```bash
INDEX_NAME="danswer_chunk"           # replace with your DB value
USER_FILE_ID="<USER_FILE_ID>"        # replace with your UUID

vespa query \
  "yql=select documentid,document_id,chunk_id from ${INDEX_NAME} where document_id = \"${USER_FILE_ID}\";" \
  "hits=5"
```

Expected:

- Before deletion finishes: you may see results under `"root" -> "children"`
- After deletion finishes: `"root" -> "children"` should be empty (0 hits)

If `vespa` CLI is not available in your Vespa image, use curl (still YQL):

```bash
curl -sG "http://localhost:8080/search/" \
  --data-urlencode "yql=select documentid,document_id,chunk_id from ${INDEX_NAME} where document_id = \"${USER_FILE_ID}\";" \
  --data-urlencode "hits=5" \
  | head -200
```

---

## What tables matter most (for user-file deletion)

- **`user_file`**: source of truth for what user files exist + their status.
- **`project__user_file`**: whether the file is attached to a project.
- **`persona__user_file`**: whether the file is attached to an assistant/persona.
- **`search_settings`**: tells you the active Vespa `index_name` to use for queries.

Optional (depends on your debugging goals):

- **`document`** and **`chunk_stats`**: used for indexing metadata. Vespa is the runtime search index; Postgres may still hold historical metadata.

---

## Vespa “database/tables” equivalent (schemas + document types)

Vespa does **not** have “databases and tables” like Postgres.
The closest equivalents are:

- **Application**: what’s deployed to Vespa (your whole search app)
- **Schema / document type**: the “collection” you query in YQL (`select ... from <schema> where ...`)
- **Fields**: the “columns” defined in the schema

### What is the “currently used database” in Vespa for Onyx?

For Onyx, the “current database/table name” you should use in Vespa is the **schema name** stored in Postgres:

- `search_settings.index_name`

So, the “current” schema is whichever `index_name` is active/current in `search_settings`.

### How to list the available schemas (“tables”) from inside the Vespa pod

#### Option 1 (recommended): inspect the deployed schema files (`*.sd`)

Inside the Vespa pod:

```bash
# List schema definition files (one .sd file per schema/document type)
find /opt/vespa -type f -name "*.sd" 2>/dev/null | head -200
```

To print just schema names:

```bash
find /opt/vespa -type f -name "*.sd" 2>/dev/null -exec basename {} .sd \; | sort -u
```

#### Option 2: infer schema(s) by querying

If you already have `INDEX_NAME`, the fact that this query works confirms the schema exists:

```bash
vespa query "yql=select documentid from ${INDEX_NAME} where true;" "hits=1"
```

#### Option 3: “visit” live documents (can be heavy)

This inspects live docs and can be expensive on large datasets—use sparingly:

```bash
vespa visit --selection "true" --field-set=[all] --wanted-document-count 1
```

---

## Where inconsistencies typically come from (and what to improve)

### 1) “File reappears right after delete”

Cause: at least one list endpoint returns `DELETING` files.

Backend improvement:

- Ensure **every endpoint that returns user files** filters out `UserFileStatus.DELETING`.
  - Known hotspots in the official repo: project file list + chat-session project files list.

### 2) UI can’t reliably show “deleting…” state

Cause: if the status polling endpoint filters out `DELETING`, the frontend can’t see it.

Improvement options:

- Return `DELETING` in the polling endpoint (and let the UI render a “deleting…” state), OR
- Make delete API return a richer payload and have the UI remove it immediately without polling.

### 3) Delete takes too long

Cause: delete happens in a background queue. If workers are overloaded, `user_file` stays `DELETING` longer.

Improvement options:

- ensure the `USER_FILE_DELETE` queue has enough worker capacity
- add better observability (metrics/logs around delete latency)

---

## Handy “one-liner” checks (copy/paste)

### Postgres: watch status change

```sql
SELECT id, status, created_at
FROM user_file
WHERE id = '<USER_FILE_ID>';
```

### Vespa: check whether any chunks remain

```bash
vespa query \
  "yql=select documentid,document_id,chunk_id from ${INDEX_NAME} where document_id = \"${USER_FILE_ID}\";" \
  "hits=5"
```


