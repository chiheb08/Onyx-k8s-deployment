# Onyx Document Storage in PostgreSQL

This reference explains how uploaded documents are stored in the Onyx database and how to inspect them directly via SQL. It covers user uploads as well as connector-sourced documents.

---

## 1. Key Tables

| Table | Purpose | Important Columns |
|-------|---------|-------------------|
| `user_file` | Tracks files uploaded via the UI (per user) | `id (UUID)`, `name`, `status`, `owner_id`, `file_id`, `chunk_count`, `created_at` |
| `document` | Canonical document entry used for search/indexing | `id (UUID string)`, `semantic_identifier`, `source`, `link`, `created_at`, `deleted` |
| `document_by_connector_credential_pair` | Bridges documents to connectors/credentials | `id (UUID)`, `connector_credential_pair_id`, `document_id`, `latest_sync_time`, `status` |
| `search_doc` | Metadata for individual chunks indexed in Vespa | `id`, `document_id`, `chunk_ind`, `blurb`, `boost`, `hidden` |
| `persona__user_file` (join) | Associates user-uploaded files to assistants/personas | `persona_id`, `user_file_id` |
| `document__tag`, `document__set`, etc. | Tagging and grouping relationships | vary |

> **Note:** The `document` table is the main entry referenced throughout indexing and search. The `user_file` table is mainly for UI & ownership tracking of uploads.

---

## 2. Sample Queries

### 2.1 List Recently Uploaded User Files
```sql
SELECT
  id,
  name,
  owner_id,
  status,
  chunk_count,
  created_at
FROM user_file
ORDER BY created_at DESC
LIMIT 20;
```
- `status` can be `UPLOADING`, `PROCESSING`, `COMPLETED`, `FAILED`, etc.
- `file_id` maps to the blob stored in S3/MinIO.

### 2.2 Find All Canonical Documents
```sql
SELECT
  id,
  semantic_identifier,
  source,
  link,
  deleted,
  created_at
FROM document
ORDER BY created_at DESC
LIMIT 20;
```
- `source` indicates the connector or `USER_FILE`.
- `semantic_identifier` is typically the human-readable title.

### 2.3 Find Documents Uploaded by a Specific User
```sql
SELECT
  uf.id AS user_file_id,
  uf.name,
  d.id AS document_id,
  d.semantic_identifier,
  uf.status,
  uf.chunk_count,
  uf.created_at
FROM user_file uf
JOIN document d ON d.id = uf.id::text  -- user_file.id is stored as UUID; document.id is stored as string
WHERE uf.owner_id = '<USER_UUID>'
ORDER BY uf.created_at DESC;
```
> Onyx stores the same UUID in both tables: `user_file.id` (UUID) and `document.id` (text). Casting may be needed when joining.

### 2.4 Show Chunks (search docs) For a Document
```sql
SELECT
  sd.id AS search_doc_id,
  sd.document_id,
  sd.chunk_ind,
  sd.blurb,
  sd.score,
  sd.created_at
FROM search_doc sd
WHERE sd.document_id = '<DOCUMENT_ID>'
ORDER BY sd.chunk_ind;
```

### 2.5 List Documents Per Connector
```sql
SELECT
  dccp.connector_credential_pair_id,
  d.semantic_identifier,
  dccp.status,
  dccp.latest_sync_time
FROM document_by_connector_credential_pair dccp
JOIN document d ON d.id = dccp.id
WHERE dccp.connector_credential_pair_id = <CC_PAIR_ID>
ORDER BY dccp.latest_sync_time DESC;
```

---

## 3. Table Relationships

```
user_file (UUID id) ─────────────────┐
                                     │ (same UUID)
document (TEXT id) ──────────────────┘
                                     │
document_by_connector_credential_pair (id references document.id)
                                     │
search_doc (document_id foreign key) ┘
```

- User uploads go into `user_file`, then become canonical entries in `document`.
- Connector documents skip `user_file` and go directly into `document` + `document_by_connector_credential_pair`.
- Each document spawns multiple rows in `search_doc` (one per chunk).

---

## 4. Referencing Files in Storage
- `user_file.file_id` points to the blob stored in S3/MinIO. Use the configured file store to download (`file_store.read_file(file_id)` in Python).
- `user_file.chunk_count` records how many chunks were generated (also used during deletion).

---

## 5. Deletion Notes
- Deleting a document should remove rows from `search_doc`, `document`, `user_file`, and any join tables.
- If you see document entries in PostgreSQL but they still appear in search, check the `document_by_cc_pair_cleanup_task` and Vespa indexes.

---

## 6. Access Tips
- Use `psql` or your preferred SQL client to run the above queries.
- For large datasets, add `WHERE` clauses (e.g., filter by `created_at`, `status`, `source`).
- Admin APIs (`/api/admin/documents`, `/api/admin/document-sets`) can also return document details without direct DB access.

---

This reference should help you inspect and audit uploaded documents directly from the database. Adjust the queries to fit your schema (EE vs. OSS) and deployment specifics.***

