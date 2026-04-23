# new_manifests_values_yaml

Manifests generated from Onyx Helm chart service model in:
`deployment/helm/charts/onyx/values.yaml`

This set is intended for your environment where you already use **your own object storage**.

## Services included (derived from values.yaml)

- PostgreSQL
- Redis
- Vespa
- OpenSearch
- API server
- Web server
- Inference model server
- Indexing model server
- Celery beat
- Celery workers: primary, docprocessing, docfetching, light, heavy, monitoring, user-file-processing
- NGINX gateway
- External S3-compatible object storage (via env vars)

## Intentionally excluded

- MinIO (`12-minio.yaml`)
- Code interpreter (`13-code-interpreter.yaml`)
- Slack bot (`14-slackbot.yaml`)

## Files

1. `00-namespace.yaml`
2. `01-secrets-template.yaml`
3. `02-configmap.yaml` (`env-configmap` name to match Helm templates)
4. `03-postgresql.yaml`
5. `04-redis.yaml`
6. `05-vespa.yaml`
7. `06-model-servers.yaml`
8. `07-api-server.yaml`
9. `08-web-server.yaml`
10. `09-celery-workers-core.yaml`
11. `10-celery-workers-additional.yaml`
12. `10-nginx-gateway.yaml`
13. `11-opensearch-pvc.yaml`
14. `11-opensearch.yaml`
15. `ARCHITECTURE.md`
16. `README.md`

## Deployment order

```bash
kubectl apply -f new_manifests_values_yaml/00-namespace.yaml
kubectl apply -f new_manifests_values_yaml/01-secrets-template.yaml
kubectl apply -f new_manifests_values_yaml/02-configmap.yaml
kubectl apply -f new_manifests_values_yaml/03-postgresql.yaml
kubectl apply -f new_manifests_values_yaml/04-redis.yaml
kubectl apply -f new_manifests_values_yaml/05-vespa.yaml
kubectl apply -f new_manifests_values_yaml/06-model-servers.yaml
kubectl apply -f new_manifests_values_yaml/11-opensearch-pvc.yaml
kubectl apply -f new_manifests_values_yaml/11-opensearch.yaml
kubectl apply -f new_manifests_values_yaml/07-api-server.yaml
kubectl apply -f new_manifests_values_yaml/08-web-server.yaml
kubectl apply -f new_manifests_values_yaml/09-celery-workers-core.yaml
kubectl apply -f new_manifests_values_yaml/10-celery-workers-additional.yaml
kubectl apply -f new_manifests_values_yaml/10-nginx-gateway.yaml
```

## Required edits before deploying

- Replace all `change-me` secrets.
- Set your real `S3_ENDPOINT_URL` and `S3_FILE_STORE_BUCKET_NAME` in `02-configmap.yaml`.
- Decide whether to keep OpenSearch enabled from day one (`ENABLE_OPENSEARCH_INDEXING_FOR_ONYX`).
- Add PVC/PV for stateful services (PostgreSQL, Vespa, OpenSearch) for production durability.
