# Vespa vs Postgres (for juniors): terminology + “what is the equivalent of a table?”

This document explains Vespa by comparing it to Postgres using simple mental models.
It’s written for someone who is comfortable with basic SQL, but new to search engines.

---

## Big picture: what problem does each system solve?

### Postgres
- Postgres is a **relational database**.
- It’s great at:
  - storing structured data (rows/columns),
  - enforcing constraints (FKs, uniqueness),
  - transactions and consistency,
  - SQL queries with joins and aggregations.

### Vespa
- Vespa is a **search + vector retrieval engine**.
- It’s great at:
  - fast text search + ranking,
  - embedding/vector search,
  - hybrid search (keyword + vector),
  - storing “documents” optimized for retrieval.

In Onyx, Postgres is the **system of record** (truth), and Vespa is the **search index** (fast retrieval).

---

## Core analogy: Postgres terms vs Vespa terms

### The “mapping table”

| Postgres term | What it means | Vespa “equivalent” | What it means |
|---|---|---|---|
| **Database** | a named container for tables | **Application** | the deployed Vespa app (schemas + config + ranking) |
| **Schema (SQL schema)** | namespace grouping tables | *(no direct 1:1)* | Vespa has namespaces, but “schema” means something else in Vespa |
| **Table** | collection of rows with a fixed set of columns | **Schema / document type** | collection of documents with defined fields |
| **Row** | one record in a table | **Document** | one document in a schema |
| **Column** | a typed field in a row | **Field** | a typed field in a document |
| **Index** | structure to speed up queries | **Indexing (per field)** | fields can be indexed for text search / attributes / vectors |
| **SQL query** | `SELECT ... FROM ... WHERE ...` | **YQL query** | `select ... from <schema> where ...` (plus ranking) |
| **JOIN** | combine tables by keys | *(not typical)* | usually denormalize into one document; some joins exist, but not like SQL |

### Important warning (common confusion)
In Vespa, the word **schema** does *not* mean the same thing as Postgres “schema”.

- In **Postgres**, schema = namespace (like `public.user_file`)
- In **Vespa**, schema = document type definition (more like a table definition)

---

## What is “the current database” in Vespa?

In Postgres you might ask:
- “Which database am I connected to?”

In Vespa you usually ask:
- “Which **schema/document type** am I querying?”

With YQL, the schema is the part after `from`:

```text
select ... from <SCHEMA_NAME> where ...
```

### In Onyx specifically
Onyx stores the “current” Vespa schema name in Postgres:

- `search_settings.index_name`

That value is what the Onyx backend uses as `<SCHEMA_NAME>` in YQL queries.

---

## “Show me my tables” in Vespa (what juniors usually mean)

In Postgres:
- `\dt` shows tables

In Vespa:
- you list **schemas** (document types)

### Option A: list schema definition files (`*.sd`) inside the Vespa pod

```bash
find /opt/vespa -type f -name "*.sd" 2>/dev/null
```

Each `something.sd` is a Vespa schema (roughly a “table”).

#### Why you see multiple `.sd` paths for the same schema (explaining your output)

When you run `find ... "*.sd"` you’ll often see the **same schema name** appear in multiple places. That’s normal.
Here’s what those paths usually mean:

- **`.../config_server/serverdb/tenants/default/sessions/7/schemas/<name>.sd`**
  - **config_server**: the Vespa component storing the deployed application config.
  - **tenants/default**: “default tenant” (common in self-hosted deployments).
  - **sessions/7**: each deploy creates a new numbered “session”.
    - Think of this like “deployment revision #7”.
  - **schemas/<name>.sd**: the raw schema file for that deployment session.

- **`.../sessions/7/.preprocessed/schemas/<name>.sd`**
  - Vespa preprocesses the application package (expands templates, validates config).
  - This is the processed version of the same schema for that session.

- **`.../filedistribution/<hash>/7/schemas/<name>.sd`**
  - Vespa distributes the deployed package to nodes.
  - The long `<hash>` is an internal identifier.
  - The important part is still **session 7** and the schema file name.

So: **multiple files ≠ multiple “tables”**. It’s usually the same “table definition” stored in different places.

#### Show only unique schema names (more readable)

```bash
find /opt/vespa -type f -name "*.sd" 2>/dev/null -exec basename {} .sd \; | sort -u
```

#### Open a schema file to see fields (“columns”)

Pick one of the returned paths (for example the `config_server/.../schemas/...sd` one) and print it:

```bash
sed -n '1,200p' /opt/vespa/var/db/vespa/config_server/serverdb/tenants/default/sessions/<N>/schemas/<SCHEMA>.sd
```

That file is where you’ll see the **field list**, which is the Vespa equivalent of “table columns”.

### Option B: infer schema names from YQL output

Query “any schema” and return `documentid`:

```bash
vespa query 'yql=select documentid from sources * where true;' 'hits=3'
```

`documentid` typically contains the document type name (schema) inside it.

---

## Example: basic queries (SQL vs YQL)

### Postgres: find latest user files

```sql
SELECT id, name, status, created_at
FROM user_file
ORDER BY created_at DESC
LIMIT 10;
```

### Vespa: fetch a few docs from a schema

```bash
INDEX_NAME="<your_schema_name>"
vespa query "yql=select documentid from ${INDEX_NAME} where true;" "hits=5"
```

### Vespa: filter by a field (similar to SQL WHERE)

```bash
INDEX_NAME="<your_schema_name>"
USER_FILE_ID="<uuid>"

vespa query \
  "yql=select documentid,document_id from ${INDEX_NAME} where document_id = \"${USER_FILE_ID}\";" \
  "hits=5"
```

---

## Why Vespa doesn’t “JOIN” like Postgres

Search engines are optimized for:
- **fast retrieval** over pre-built indexes

Joins are expensive in that world, so the typical pattern is:
- **denormalize**: store the fields you need for search together in the document

In Onyx:
- Postgres keeps the normalized truth (relationships, constraints)
- Vespa stores the searchable version (chunks, embeddings, metadata) for speed

---

## Quick cheat sheet

- If you want **truth / constraints / relationships** → Postgres
- If you want **search / ranking / embeddings** → Vespa
- “Table in Vespa” ≈ **schema / document type**
- “Row in Vespa” ≈ **document**
- “Column in Vespa” ≈ **field**
- “Which schema am I using?”:
  - in YQL: it’s the name after `from`
  - in Onyx: look at `search_settings.index_name`


