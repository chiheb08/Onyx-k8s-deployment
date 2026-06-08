# Resource Sizing — 50 Concurrent Users

Profile assumptions:
- ~50 active users, mix of chat + file upload + connector indexing
- vLLM runs **externally** (not counted in these totals)
- Embedding/rerank via bundled `onyx-model-server` pods

## Cluster minimum (requests)

| Component | Replicas | CPU req | Memory req |
|-----------|----------|---------|------------|
| onyx-api-server | 2 | 2 | 4 Gi |
| onyx-webserver | 2 | 1 | 2 Gi |
| onyx-nginx | 2 | 0.4 | 512 Mi |
| onyx-postgres | 1 | 1 | 4 Gi |
| onyx-redis | 1 | 0.25 | 512 Mi |
| onyx-opensearch | 1 | 1 | 4 Gi |
| onyx-minio | 1 | 0.5 | 1 Gi |
| onyx-inference-model | 2 | 4 | 8 Gi |
| onyx-indexing-model | 2 | 4 | 8 Gi |
| **Celery beat** | 1 | 0.5 | 512 Mi |
| **celery-worker-primary** | 2 | 1 | 4 Gi |
| **celery-worker-light** | 1 | 0.5 | 1 Gi |
| **celery-worker-heavy** | 1 | 0.5 | 1 Gi |
| **celery-worker-docprocessing** | 2 | 2 | 4 Gi |
| **celery-worker-docfetching** | 1 | 0.5 | 2 Gi |
| **celery-worker-user-file-processing** | 2 | 1 | 2 Gi |
| **celery-worker-monitoring** | 1 | 0.25 | 512 Mi |
| **Total (approx)** | **24 pods** | **~20 CPU** | **~47 Gi** |

Add **25–30% headroom** for OpenShift system pods → plan a worker pool of **~26 CPU / 60 Gi** allocatable minimum.

## Celery workers (explicit Deployments)

| Deployment | Queues | Replicas | Why |
|------------|--------|----------|-----|
| `onyx-celery-beat` | scheduler | 1 | Must be singleton |
| `onyx-celery-worker-primary` | `celery` | 2 | General async jobs |
| `onyx-celery-worker-light` | sync, deletion, cleanup | 1 | Metadata sync |
| `onyx-celery-worker-heavy` | pruning, permissions | 1 | Heavy connector ops |
| `onyx-celery-worker-docprocessing` | `docprocessing` | 2 | Connector indexing throughput |
| `onyx-celery-worker-docfetching` | `connector_doc_fetching` | 1 | Connector fetch |
| `onyx-celery-worker-user-file-processing` | `user_file_*` | 2 | **File upload/delete** |
| `onyx-celery-worker-monitoring` | `monitoring` | 1 | Queue metrics |

`celery-worker-scheduled-tasks` is **omitted** (Craft disabled).

## Storage

| PVC | Size |
|-----|------|
| Postgres | 100 Gi |
| OpenSearch | 30 Gi |
| MinIO | 200 Gi |

## OpenSearch JVM

```
OPENSEARCH_JAVA_OPTS=-Xms1g -Xmx1g
memory limit: 6Gi
```

Do **not** set heap above ~50% of the container memory limit. If you increase OpenSearch memory, increase heap proportionally.

## Scaling beyond 50 users

| Bottleneck symptom | Scale first |
|--------------------|-------------|
| Slow chat responses | vLLM replicas / GPU; API replicas |
| File upload queue backlog | `celery-worker-user-file-processing` replicas |
| Connector indexing slow | `celery-worker-docprocessing` replicas |
| OpenSearch OOM | OpenSearch memory + heap |
| Redis queue depth high | Redis memory; worker replicas |
