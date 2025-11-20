# Document `source_type` (DocumentSource) Reference

This guide explains how Onyx tracks the **origin of each document** (“source type”), where that information lives in the database, how to inspect it in a Kubernetes deployment, and how to interpret each value.

---

## 1. What is `source_type`?

Every row in the `document` table has a `source` column. It stores a string from the `DocumentSource` enum defined in `backend/onyx/configs/constants.py`. This value tells you where the document came from, e.g. `user_file`, `confluence`, `slack`, `github`, etc.

Typical pipeline:

```
User upload → user_file.id = <UUID>
           → document.id = '<UUID>' (string)
           → document.source = 'user_file'

Connector run → document.id = <UUID string>
              → document.source = 'confluence' (or other connector-specific value)
```

You can use this column to filter documents by origin, audit ingestion, or troubleshoot misrouted data.

---

## 2. Enumerated values

The `DocumentSource` enum includes dozens of values. The table below lists the most common ones (see `backend/onyx/configs/constants.py` for the full list).

| Value | Meaning / Connector |
|-------|---------------------|
| `user_file` | File uploaded via the Onyx UI/API |
| `ingestion_api` | Document pushed through the ingestion API without a specific connector |
| `confluence` | Atlassian Confluence pages/blog posts |
| `google_drive` | Google Drive documents/sheets/slides |
| `sharepoint` | Microsoft SharePoint files |
| `s3`, `r2`, `google_cloud_storage`, `oci_storage` | Object storage connectors |
| `slack`, `teams`, `discord`, `zulip` | Chat integrations |
| `github`, `gitlab`, `bitbucket` | Source-control integrations |
| `jira`, `linear`, `asana`, `clickup` | Work-management systems |
| `notion`, `guru`, `slab`, `bookstack`, `document360`, `outline` | Knowledge base tools |
| `zendesk`, `freshdesk`, `hubspot`, `salesforce`, `productboard` | Support/CRM tools |
| `mock_connector` | Test data from the mock connector |
| `not_applicable` | Fallback when no specific source applies |

You can retrieve the exact descriptive text from the `DocumentSourceDescription` dict in the same file.

---

## 3. Where the data lives

### 3.1 Tables

| Table | Field | Description |
|-------|-------|-------------|
| `document` | `source` | Primary `source_type` value |
| `document_by_connector_credential_pair` | `connector_credential_pair_id`, `id` (same as `document.id`) | Links documents to the connector+credential that produced them |
| `user_file` | `id` / `owner_id` | Used for UI metadata. All user-uploaded files have `document.source = 'user_file'` |
| `connector` | `source` column | Identifies what type of connector (e.g., `confluence`, `github`) – often matches the document source |

### 3.2 Joins

To see documents along with their connector info:

```sql
SELECT
  d.id,
  d.semantic_identifier,
  d.source AS source_type,
  c.name AS connector_name,
  c.source  AS connector_source,
  dccp.latest_sync_time
FROM document d
LEFT JOIN document_by_connector_credential_pair dccp ON d.id = dccp.id
LEFT JOIN connector_credential_pair ccp ON ccp.id = dccp.connector_credential_pair_id
LEFT JOIN connector c ON c.id = ccp.connector_id
ORDER BY d.created_at DESC
LIMIT 50;
```

This tells you both the document’s own `source_type` and which connector credential produced it.

---

## 4. Inspecting source types in Kubernetes

1. **Find the PostgreSQL pod**:
   ```bash
   kubectl get pods -n <namespace>
   # look for postgresql-0 (from 02-postgresql.yaml)
   ```

2. **Exec into the pod**:
   ```bash
   kubectl exec -it postgresql-0 -n <namespace> -- /bin/bash
   ```

3. **Get the DB password** (from secret):
   ```bash
   kubectl get secret postgresql-secret -n <namespace> \
     -o jsonpath='{.data.postgres-password}' | base64 -d
   ```

4. **Connect with psql**:
   ```bash
   psql -U postgres -d postgres
   ```

5. **Run queries** (examples below). Exit with `\q` when done.

> For detailed steps see `documentation/VIEW-DOCUMENTS-IN-K8S.md`.

---

## 5. Useful SQL queries

### 5.1 List documents with source type
```sql
SELECT
  id,
  semantic_identifier,
  source AS source_type,
  created_at
FROM document
ORDER BY created_at DESC
LIMIT 20;
```

### 5.2 Count documents per source
```sql
SELECT
  source AS source_type,
  COUNT(*) AS doc_count
FROM document
GROUP BY source
ORDER BY doc_count DESC;
```

### 5.3 Filter by specific source
```sql
SELECT id, semantic_identifier, created_at
FROM document
WHERE source = 'confluence'
ORDER BY created_at DESC
LIMIT 20;
```

### 5.4 Join user uploads with document table
```sql
SELECT
  uf.id AS user_file_id,
  uf.name,
  d.source AS source_type,
  uf.status,
  uf.created_at
FROM user_file uf
JOIN document d ON d.id = uf.id::text
ORDER BY uf.created_at DESC
LIMIT 20;
```
> Expect `source_type = 'user_file'` for direct uploads.

### 5.5 Connectors & source type
```sql
SELECT
  d.id,
  d.source AS doc_source,
  c.name AS connector_name,
  c.source AS connector_type,
  dccp.latest_sync_time
FROM document d
JOIN document_by_connector_credential_pair dccp ON d.id = dccp.id
JOIN connector_credential_pair ccp ON ccp.id = dccp.connector_credential_pair_id
JOIN connector c ON c.id = ccp.connector_id
ORDER BY dccp.latest_sync_time DESC
LIMIT 20;
```

---

## 6. How connectors set `source_type`

- Each connector (e.g., Confluence, Google Drive, Slack) sets the `source` field when writing `Document` objects.
- For user file uploads handled by `process_single_user_file`, the source is hard-coded to `DocumentSource.USER_FILE`.
- Custom ingestion via the API can set the `source` value explicitly. If omitted, it defaults to `ingestion_api`.

You can verify this by searching for `DocumentSource` references in the connector code (e.g., `backend/onyx/connectors/*`).

---

## 7. Troubleshooting tips

| Symptom | Checks |
|---------|--------|
| Source appears as `not_applicable` | The connector may not set `DocumentSource`; inspect connector logs and ensure it calls `DocumentSource.<name>` |
| Documents have `user_file` but should be `file` | User uploads always map to `user_file`. Connector-managed file ingestion uses `file` or a specific storage connector (e.g., `s3`) |
| Need human-readable description | Look up `DocumentSourceDescription` dict in `backend/onyx/configs/constants.py` |
| Need per-connector statistics | Use the “count per source” query or join with connector tables |

---

## 8. Summary

- `source_type` is stored in `document.source` as a string from `DocumentSource`.
- Inspect it via SQL (`SELECT source FROM document …`).
- For Kubernetes deployments, exec into the PostgreSQL pod and run the queries above.
- Use joins with `document_by_connector_credential_pair`/`connector` to see which connector generated each document.
- Refer to `backend/onyx/configs/constants.py` for the authoritative list of allowed source types and their meaning.


