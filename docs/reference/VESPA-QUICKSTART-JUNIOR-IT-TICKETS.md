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

In Onyx:

- Postgres stores truth (e.g. `user_file`, `chat_message`, etc.)
- Vespa stores the **search index**

So:
- if a “row” is deleted in Postgres, you also need to remove the corresponding “document(s)” from Vespa
- otherwise search results can still show stale content

---

## “If you remember only 3 things”

1) **Schema** in Vespa is closest to a **table definition**.
2) Choose indexing type carefully:
   - `index` = searchable text
   - `attribute` = fast filters/sorts/groups
   - `summary` = returned in results
3) Vespa is built for search/ranking, not joins—feed documents shaped for retrieval.

