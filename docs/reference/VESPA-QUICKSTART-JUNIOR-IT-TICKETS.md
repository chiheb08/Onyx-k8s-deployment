# Vespa Quickstart (easy version): build a search app for IT support tickets

This is a **junior-friendly** summary of the Vespa quickstart tutorial, but using a different example: **IT support tickets** (instead of films).

Source tutorial (original): [Vespa Quickstart – How to build an Application with Vespa](https://blog.vespa.ai/vespa-quickstart-how-to-set-up-an-application-with-vespa/).

---

## Goal: what we are building

We want a system where we can:

- **feed** (upload) IT support tickets into Vespa
- **search** them quickly by title / description
- **filter** by things like priority or created year
- **return** useful fields in the response

In Postgres terms, you might think:

- “I have a `tickets` table, I want to run `SELECT ... WHERE ...` fast.”

In Vespa terms, you think:

- “I have a **schema** (document type) called `ticket`, and I want to query it with **YQL**.”

---

## Vespa words you must know (simple)

### Document
A **document** is one “record” (similar to a row).

Example ticket document (what we feed to Vespa):

```json
{
  "id": "TCK-1001",
  "fields": {
    "ticket_id": "TCK-1001",
    "title": "VPN not connecting",
    "description": "User cannot connect to VPN, error 809. Started after password reset.",
    "priority": "P1",
    "created_year": 2026
  }
}
```

### Schema

A **schema** defines:

- the list of fields (“columns”)
- each field’s type
- how each field is stored/indexed

You usually create:

- **1 schema** per “collection” you want to search (tickets, articles, products, etc.)

---

## Why Vespa has `index`, `summary`, and `attribute` (the most important part)

When defining a field you choose how Vespa stores it. This is the key idea:

### `index` (searchable text index)
Use `index` when you want to **search** inside the field text.

- Like “full text index”
- Good for: `title`, `description`, `content`

Example:
- You want `"VPN not connecting"` to match queries like `"vpn"` or `"connecting"`.

### `summary` (return the field in search results)
Use `summary` when you want the field to show up in the response payload.

- Like “include this column in SELECT output”
- Good for: `ticket_id`, `title`, `priority`, small snippets of `description`

If you don’t mark a field as summary (or otherwise return it), you might still be able to filter/rank on it, but it won’t be included in the returned hits by default.

### `attribute` (fast filtering/sorting/grouping)
Use `attribute` when you want fast operations like:

- `WHERE created_year > 2025`
- sorting (`ORDER BY created_year DESC`)
- grouping / facets (e.g., count tickets per priority)

Attributes are optimized for fast lookups and aggregations.

**Why we use `attribute` for a year field**:

- year is a number
- we often filter (`created_year > 2025`) or sort by it
- we do NOT typically do “contains text search” inside a number

So for `created_year`, `attribute` is the right choice.

### Common pattern

- Text you want to search: `index` (+ usually `summary`)
- Fields you want to filter/sort/group: `attribute` (+ often `summary`)

---

## Step-by-step: build the app configuration

We will define a Vespa app with one schema: `it_ticket`.

### 1) Define the schema + document fields (conceptual)

We will store these fields:

- `ticket_id` (string)
- `title` (string)
- `description` (string)
- `priority` (string)
- `created_year` (int)

### 2) Recommended indexing choices (with explanations)

- `ticket_id`: `summary`
  - we want to return the ID in results
  - we usually don’t “search inside” IDs
- `title`: `index`, `summary`
  - we want to search it
  - we want to show it in results
- `description`: `index`, `summary`
  - we want to search it
  - we want to return a snippet in results
- `priority`: `attribute`, `summary`
  - we want fast filtering (P1 only) and faceting
  - we want to display it in results
- `created_year`: `attribute`, `summary`
  - we want fast filtering / sorting / grouping by year
  - we might display it too

---

## Fieldsets (why they exist)

A **fieldset** is a named group of fields used for searching.

Example:
- Search in `title` and `description` together as your default search space.

This is helpful because you can say “search the default fieldset” instead of listing fields every time.

---

## Feeding data (what it really means)

Feeding is the process of sending documents into Vespa.

Important:
- Vespa is not a relational database. You usually feed **complete documents**.
- If a document changes, you update (feed) it again.

---

## Querying (YQL) — easy examples

Assume your schema name is `it_ticket`.

### 1) Basic “show me something”

```bash
vespa query 'yql=select documentid, ticket_id, title from it_ticket where true;' 'hits=5'
```

### 2) Keyword search (simple)

```bash
vespa query "yql=select * from it_ticket where title contains 'vpn';" "hits=5"
```

### 3) Safer user input: `userQuery()`

`userQuery()` is recommended because it parses user input safely (avoids weird query injection).

```bash
vespa query "yql=select * from it_ticket where userQuery();" "query=vpn not connecting" "hits=5"
```

### 4) Filter by year (attribute field)

```bash
vespa query "yql=select * from it_ticket where userQuery() AND created_year > 2025;" "query=vpn" "hits=5"
```

This is fast because `created_year` is an `attribute`.

---

## How this maps to Onyx (why you care)

Onyx uses Vespa like a **search index** and Postgres like the **source of truth**.
This section explains (at a technical level) what actually happens in Onyx when data is ingested and queried.

### 1) What Onyx ingests (“documents”)

Onyx converts many sources into a common internal model:

- A **`Document`** with:
  - `id`
  - `sections` (text or images)
  - `semantic_identifier` (what users see in the UI)
  - metadata (owners, tags, access control, etc.)

This is the object you see throughout the backend (`backend/onyx/connectors/models.py` in the official repo).

Where these documents come from:

- **Connectors** (Google Drive, Confluence, Slack, etc.) emit batches of `Document`s.
- **Ingestion API** can also accept “documents” directly (same model, `from_ingestion_api` flag).
- **User uploads** (files uploaded via UI) are treated as documents too:
  - for user files, Onyx uses the `user_file.id` as the document ID during indexing so the file can later be updated/deleted consistently.

### 2) Onyx ingestion/indexing pipeline (the “ETL” into Vespa)

Think of this as: **take raw docs → prepare → chunk → embed → write to Vespa**.

In the official repo, the core flow is implemented in `backend/onyx/indexing/indexing_pipeline.py`:

- **Prepare / DB upsert (Postgres first)**
  - Onyx upserts document metadata into Postgres (so Postgres stays the system of record).
  - This includes tags/metadata needed for UI and permission logic.
- **Filter**
  - Skip empty or extremely large documents to avoid indexing useless data or OOM crashes.
- **Chunk**
  - Split documents into chunks (because search + LLM context works on chunks, not whole files).
- **Embed**
  - Create vectors for each chunk using the active embedding model.
- **Write to “document index”**
  - Onyx writes the chunks to the configured index backend.
  - In most deployments this is **Vespa**.

Under the hood, the “write to Vespa” step calls a helper which tries a big batch first, and if it fails, retries document-by-document to isolate failures:

- `backend/onyx/indexing/vector_db_insertion.py` (`write_chunks_to_vector_db_with_backoff`)

### 3) How Onyx chooses the Vespa schema (“which table am I writing to?”)

Onyx stores the active index configuration in Postgres in `search_settings`.

Key field:

- `search_settings.index_name`

That `index_name` is passed into the Vespa client as the Vespa **schema/document type name**.

In the official repo:

- `backend/onyx/document_index/factory.py` chooses the index implementation:
  - typically `VespaIndex(index_name=search_settings.index_name, ...)`
  - it can also support a **secondary index** during model migrations / switchover

### 4) How Onyx queries Vespa (keyword + vector “hybrid search”)

At query time, Onyx usually does **hybrid retrieval**:

1) Compute a **query embedding** (vector) for the user’s query text.
2) Combine:
   - keyword matching (text index)
   - vector similarity (embedding search)
   - filters (source type, document sets, user file IDs, etc.)
3) Ask Vespa for top chunks, ranked.

In the official repo:

- `backend/onyx/context/search/retrieval/search_runner.py` calls `document_index.hybrid_retrieval(...)`
- The Vespa implementation is in `backend/onyx/document_index/vespa/index.py` (`VespaIndex.hybrid_retrieval`)

What’s happening conceptually:

- **Filters** are first built from the request (examples: source types, document sets, user file IDs, ACL, tenant).
- Onyx then issues a Vespa query that includes:
  - text query parsing via `userInput(@query)` (safe parsing of user text)
  - a grammar configuration like `weakAnd` (a Vespa setting that impacts matching behavior)
  - a ranking profile (example: `admin_search`) to control scoring

You can see this style clearly in `VespaIndex.admin_retrieval` where YQL is built from a base select + filter clauses + `userInput(@query)`.

Important concept:

- **`hybrid_alpha`** controls the balance:
  - closer to 0 → mostly keyword
  - closer to 1 → mostly semantic/vector

### 4.1) Why Onyx does “two-step retrieval” (IDs first, then chunk fetch)

A common performance pattern in Onyx is:

1) **Retrieve top matching chunk IDs** (fast ranked retrieval)
2) **Fetch full chunk payloads by ID** (id-based retrieval)

This is visible in `search_runner.py`:

- it collects document IDs from search results
- then calls `document_index.id_based_retrieval(...)` to pull chunk content for those IDs

This keeps the initial ranking query cheaper and makes the “fetch content” step more controlled.

### 4.2) Multi-tenancy (why tenant_id shows up in queries)

If Onyx is running in multi-tenant mode, Vespa documents include a `tenant_id` field.
Onyx then filters queries to only return documents from the active tenant.

You’ll see tenant usage in Vespa code paths (e.g., queries selecting IDs where `tenant_id contains "<tenant>"`).

### 5) Why deletion inconsistencies happen (Postgres vs Vespa)

Because Postgres is the truth, and Vespa is a search index:

- If a file/document is “deleted” in Postgres, but its chunks are still in Vespa, search can still return them.
- If the backend marks a record as “DELETING” (soft state) but some list endpoints don’t filter it, the UI can show it again briefly.

That’s why Onyx typically does deletion in two phases:

1) Mark “deleting” in Postgres (so UI can hide it immediately)
2) Asynchronously delete the document/chunks from Vespa, then remove the Postgres row

---

## “If you remember only 3 things”

1) **Schema** in Vespa is closest to a **table definition**.
2) Choose indexing type carefully:
   - `index` = searchable text
   - `attribute` = fast filters/sorts/groups
   - `summary` = returned in results
3) Vespa is built for search/ranking, not joins—feed documents shaped for retrieval.

