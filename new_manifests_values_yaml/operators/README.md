# Operator pilot manifests (OpenShift)

Used with: `implementation/OPENSHIFT-OPERATOR-PILOT-STEP-BY-STEP.md`

## Operators

| Operator | Install | Manifests here |
|----------|---------|----------------|
| **CloudNativePG** | Cluster admin — see step-by-step doc | `cnpg/` |
| **OpenSearch Kubernetes Operator** | Cluster admin — Helm | `opensearch/` |

## Before apply

1. Replace `<STORAGE_CLASS>` in cluster YAML files.
2. Replace `<your-registry>/onyx-opensearch:3.4.0-uid-arbitrary` after building `opensearch-custom/Dockerfile`.
3. Fill MinIO keys in `cnpg/01-backup-s3-secret.yaml`.
4. Bind SCC to `onyx-data-plane` ServiceAccount if pods fail on OpenShift.

## Apply order

```bash
oc apply -f 00-serviceaccount-openshift.yaml
oc apply -f cnpg/01-backup-s3-secret.yaml
oc apply -f cnpg/02-cluster-pilot.yaml
# After OpenSearch operator is installed:
oc apply -f opensearch/02-opensearch-cluster-pilot.yaml
```
