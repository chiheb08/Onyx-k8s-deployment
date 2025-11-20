# Onyx Document Storage in PostgreSQL

This reference explains how uploaded documents are stored in the Onyx database and how to inspect them directly via SQL. It covers user uploads as well as connector-sourced documents.

---

## 1. Key Tables

| Table | Purpose | Important Columns |
|-------|---------|-------------------|
| `user_file` | Tracks files uploaded via the UI (per user) | `id (UUID)`, `name`, `status`, `owner_id`, `file_id`, `chunk_count`, `created_at` |
| `document` | Canonical document entry used for search/indexing | `id (UUID string)`, `semantic_id`, `link`, `doc_updated_at`, `deleted`, `created_at` |
| `document_by_connector_credential_pair` | Bridges documents to connectors/credentials | `id` (FK to `document.id`), `connector_id`, `credential_id`, `has_been_indexed` |
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
  semantic_id,
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
  d.semantic_id,
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
  d.id,
  d.semantic_identifier,
  d.source            AS doc_source,
  dccp.has_been_indexed,
  ccp.name            AS connector_name,
  ccp.last_successful_index_time
FROM document d
LEFT JOIN document_by_connector_credential_pair dccp
       ON d.id = dccp.id
LEFT JOIN connector_credential_pair ccp
       ON ccp.connector_id = dccp.connector_id
      AND ccp.credential_id = dccp.credential_id
WHERE ccp.id = <CONNECTOR_CREDENTIAL_PAIR_ID>
ORDER BY ccp.last_successful_index_time DESC
LIMIT 50;
```

### 2.6 List All Documents With Their Source Type (user uploads + connector docs)
```sql
SELECT
  d.id                      AS document_id,
  d.semantic_id             AS title,
  COALESCE(
      c.source,
      CASE WHEN uf.id IS NOT NULL THEN 'user_file' ELSE 'ingestion_api' END
  )                         AS source_type,
  COALESCE(uf.name, d.semantic_id) AS original_name,
  uf.owner_id               AS uploaded_by_user,
  c.name                    AS connector_name,
  c.source                  AS connector_type,
  d.created_at
FROM document d
LEFT JOIN user_file uf
       ON uf.id::text = d.id
LEFT JOIN document_by_connector_credential_pair dccp
       ON d.id = dccp.id
LEFT JOIN connector_credential_pair ccp
       ON ccp.connector_id = dccp.connector_id
      AND ccp.credential_id = dccp.credential_id
LEFT JOIN connector c
       ON c.id = ccp.connector_id
ORDER BY d.created_at DESC
LIMIT 50;
```
- `source_type` is the canonical origin (`user_file`, `confluence`, `slack`, etc.).
- `original_name` surfaces the uploaded filename for user files; connector entries fall back to the document’s semantic identifier.
- `connector_name`/`connector_type` populate only when the document was ingested via a connector; they stay `NULL` for pure user uploads.

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

