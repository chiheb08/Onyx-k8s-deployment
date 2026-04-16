# Onyx Architecture (values.yaml coverage, external S3)

```mermaid
flowchart LR
  U[Users] --> N[nginx gateway]
  N --> W[web-server]
  N --> A[api-server]

  W --> A

  A --> PG[(PostgreSQL)]
  A --> R[(Redis)]
  A --> V[(Vespa)]
  A --> O[(OpenSearch)]

  B0[celery-beat] --> R
  B0 --> PG

  B1[celery-worker-primary] --> PG
  B1 --> R
  B1 --> V

  B2[celery-worker-docprocessing] --> PG
  B2 --> R
  B2 --> V
  B2 --> I[indexing-model-server]
  B2 --> S[(S3-compatible object storage)]

  B3[celery-worker-docfetching] --> PG
  B3 --> R

  B4[celery-worker-light] --> R
  B4 --> V
  B4 --> O

  B5[celery-worker-heavy] --> R
  B5 --> PG

  B6[celery-worker-monitoring] --> PG
  B6 --> R

  B7[celery-worker-user-file-processing] --> S
  B7 --> V
  B7 --> R

  M[inference-model-server] <--> A

  A --> M

  subgraph Storage
    PG
    R
    V
    O
    S
  end
```

## Linking summary

- `nginx` exposes the external endpoint and routes to `web-server` and `api-server`.
- `api-server` is the synchronous path (auth, chat, uploads orchestration).
- Celery workers run the asynchronous pipeline (document fetch, processing, indexing, sync).
- `Redis` coordinates background/queue state.
- `Vespa` provides retrieval/vector search.
- `OpenSearch` provides text-oriented indexing/search capability.
- Object binaries and uploaded files are stored in your **external S3-compatible storage**.
