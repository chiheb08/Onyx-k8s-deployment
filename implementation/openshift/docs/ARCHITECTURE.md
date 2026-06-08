# Onyx OpenShift Architecture

## Service dependency matrix

| Consumer → Provider | postgres | redis | opensearch | minio | inference-model | indexing-model | api | web | nginx |
|---------------------|:--------:|:-----:|:----------:|:-----:|:---------------:|:--------------:|:---:|:---:|:-----:|
| **api-server** | ✓ | ✓ | ✓ | ✓ | ✓ | — | — | — | — |
| **webserver** | — | — | — | — | — | — | ✓ | — | — |
| **nginx** | — | — | — | — | — | — | ✓ | ✓ | — |
| **celery workers** | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | — | — |
| **inference-model** | ✓ | — | — | — | — | — | — | — | — |
| **indexing-model** | ✓ | — | — | — | — | — | — | — | — |

## Startup order (enforced by initContainers)

```
1. postgres, redis, opensearch, minio     (StatefulSets — parallel)
2. inference-model, indexing-model        (after postgres)
3. api-server                             (after all data + inference)
4. celery beat + workers                    (after api + all infra)
5. webserver                              (after api)
6. nginx + Route                          (after api + web)
```

## Celery queues (background / Redis DB 15)

| Queue | Purpose |
|-------|---------|
| `user_file_processing` | Index uploaded files |
| `user_file_delete` | Delete files (priorities `:1` = HIGH) |
| `user_file_project_sync` | Project-scoped search sync |
| `celery` | Primary worker |
| `docprocessing` / `docfetching` | Connector pipelines |
| `monitoring` | Queue depth metrics |

## Data flows

### Chat (vLLM)

```
User → Route → nginx → webserver → api-server → Postgres (llm_provider config)
                                              → vLLM (openai_compatible HTTP)
```

### File upload + RAG

```
User → api-server → MinIO (raw file)
                 → Postgres (user_file PROCESSING)
                 → Redis (process_single_user_file)
                 → celery-worker-user-file-processing
                      → indexing-model (embed)
                      → OpenSearch (chunks)
                      → MinIO (plaintext cache)
                      → Postgres (COMPLETED)
```

### File delete

```
User → api-server → Postgres (DELETING)
                 → Redis (delete_single_user_file on user_file_delete:1)
                 → celery-worker-user-file-processing → OpenSearch delete → MinIO delete → Postgres DELETE
```

## Critical production settings

| Setting | Value | Why |
|---------|-------|-----|
| `OPENSEARCH_JAVA_OPTS` | `-Xms512m -Xmx512m` | Prevents OOM kill |
| OpenSearch memory limit | `1536Mi` | Headroom for off-heap |
| `LLM_SOCKET_READ_TIMEOUT` | `180` | Slow vLLM responses |
| nginx `proxy_read_timeout` | `900s` | Long chat sessions |
| `webserver HOSTNAME` | `0.0.0.0` | Health checks in container |
| Image tag pin | `v4.0.5` or tested tag | Reproducibility |

## What is NOT in this deployment

- **vLLM** — deploy separately; configure via Admin UI
- **Craft / sandboxes** — disabled (`ENABLE_CRAFT=false`)
- **Slack/Discord bots** — disabled in Helm overlay
- **Code interpreter** — disabled (enable if needed)
- **cert-manager** — OpenShift Route handles edge TLS
