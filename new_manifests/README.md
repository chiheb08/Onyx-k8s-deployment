# New Onyx Manifests (Stable Baseline)

This folder contains a clean Kubernetes baseline for a fresh Onyx deployment focused on stability.

## Target version

- Onyx components: `v3.1.1`
- Vespa: `8.609.39`

## Files

1. `00-namespace.yaml`
2. `01-secrets-template.yaml`
3. `02-configmap.yaml`
4. `03-postgresql.yaml`
5. `04-redis.yaml`
6. `05-vespa.yaml`
7. `06-model-servers.yaml`
8. `07-api-server.yaml`
9. `08-web-server.yaml`
10. `09-celery-workers.yaml`
11. `10-nginx-gateway.yaml`
12. `ARCHITECTURE.md`

## Deployment order

```bash
kubectl apply -f new_manifests/00-namespace.yaml
kubectl apply -f new_manifests/01-secrets-template.yaml
kubectl apply -f new_manifests/02-configmap.yaml
kubectl apply -f new_manifests/03-postgresql.yaml
kubectl apply -f new_manifests/04-redis.yaml
kubectl apply -f new_manifests/05-vespa.yaml
kubectl apply -f new_manifests/06-model-servers.yaml
kubectl apply -f new_manifests/07-api-server.yaml
kubectl apply -f new_manifests/08-web-server.yaml
kubectl apply -f new_manifests/09-celery-workers.yaml
kubectl apply -f new_manifests/10-nginx-gateway.yaml
```

## Required edits before apply

- Replace secret values in `01-secrets-template.yaml`.
- Set real S3 endpoint and bucket in `02-configmap.yaml`.
- Set your production domain in `02-configmap.yaml` (`WEB_DOMAIN`, `DOMAIN`).
- Add persistence (PVC/PV) for PostgreSQL and Vespa before production use.

## Notes

- This baseline keeps `ENABLE_OPENSEARCH_INDEXING_FOR_ONYX=false` to reduce moving parts during initial stabilization.
- After stable operation, OpenSearch can be introduced as a controlled change.
