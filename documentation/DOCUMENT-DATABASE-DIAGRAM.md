# Onyx Document Database Relationships

```mermaid
erDiagram
    USER_FILE ||--|| DOCUMENT : "shares UUID"
    USER_FILE {
        uuid id PK
        uuid owner_id
        text name
        text status
        text file_id
        int chunk_count
        timestamptz created_at
    }
    DOCUMENT {
        text id PK
        text semantic_identifier
        text source
        text link
        bool deleted
        timestamptz created_at
    }

    DOCUMENT ||--o{ SEARCH_DOC : "1 document → many chunks"
    SEARCH_DOC {
        serial id PK
        text document_id FK
        int chunk_ind
        text blurb
        bool hidden
        timestamptz created_at
    }

    DOCUMENT ||--o{ DOCUMENT_BY_CC_PAIR : "optional"
    CONNECTOR ||--o{ DOCUMENT_BY_CC_PAIR : "connector owns docs"
    CREDENTIAL ||--o{ DOCUMENT_BY_CC_PAIR : "credential owns docs"
    DOCUMENT_BY_CC_PAIR {
        text id FK
        int connector_id FK
        int credential_id FK
        bool has_been_indexed
    }

    CONNECTOR ||--o{ CONNECTOR_CREDENTIAL_PAIR : "connector has many CC pairs"
    CREDENTIAL ||--o{ CONNECTOR_CREDENTIAL_PAIR : "credential reused"
    CONNECTOR_CREDENTIAL_PAIR {
        int connector_id PK
        int credential_id PK
        int id_seq
        text name
        text status
        timestamptz last_successful_index_time
        bool is_user_file
    }

    PERSONA ||--o{ PERSONA__USER_FILE : "assistants attach uploads"
    USER_FILE ||--o{ PERSONA__USER_FILE : ""
    PERSONA__USER_FILE {
        int persona_id FK
        uuid user_file_id FK
    }

    DOCUMENT ||--o{ DOCUMENT__TAG : ""
    TAG ||--o{ DOCUMENT__TAG : ""
```

**Legend**

- `|` = exactly one, `o` = zero or more
- USER_FILE and DOCUMENT share the same UUID (user upload row + canonical doc row)
- DOCUMENT_BY_CC_PAIR links canonical documents to connectors/credentials
- SEARCH_DOC rows are the individual chunks indexed in Vespa/pgvector
- CONNECTOR_CREDENTIAL_PAIR stores connector+credential configurations
- PERSONA__USER_FILE shows how assistants/personas consume user uploads
- DOCUMENT__TAG (not expanded) represents tagging relationships

