# Differences: `new_manifests_values_yaml/` vs current `manifests/`

This document compares the new Helm-values-driven manifests with your current manually maintained manifests.

## 1) Source of truth model

- **Current folder (`manifests/`)**
  - Hand-crafted manifests built around your custom deployment evolution.
- **New folder (`new_manifests_values_yaml/`)**
  - Service coverage aligned to upstream Onyx Helm chart values model (`deployment/helm/charts/onyx/values.yaml`).

---

## 2) Service coverage differences

## Added in `new_manifests_values_yaml/`

1. **OpenSearch** (`11-opensearch.yaml`)
2. **MinIO object storage** (`12-minio.yaml`)
3. **Code Interpreter** (`13-code-interpreter.yaml`)
4. **Slack bot** (`14-slackbot.yaml`)
5. **Celery monitoring worker** (inside `10-celery-workers-additional.yaml`)

Your current `manifests/` does not include these workloads as first-class deployables.

## Existing in both (with differences)

- PostgreSQL
- Redis
- Vespa
- API server
- Web server
- Inference/indexing model servers
- Celery beat/primary/light/heavy/docfetching/docprocessing/user-file-processing
- NGINX gateway

---

## 3) Naming and configuration contract changes

## ConfigMap

- **Current:** `onyx-config`
- **New:** `env-configmap` (matches Helm templates)

## Secret names and key schema

- **Current:**
  - `postgresql-secret` (`POSTGRES_USER`, `POSTGRES_PASSWORD`)
  - `redis-secret` (`REDIS_PASSWORD`)
  - S3 often custom / vault-backed in other files
- **New (Helm-style):**
  - `onyx-postgresql` (`username`, `password`)
  - `onyx-redis` (`redis_password`)
  - `onyx-objectstorage` (`s3_aws_access_key_id`, `s3_aws_secret_access_key`, `rootUser`, `rootPassword`)
  - `onyx-opensearch` (`opensearch_admin_username`, `opensearch_admin_password`)
  - `onyx-slackbot` (bot token keys)

This is a **major operational difference**: your automation/secret management must map to these names/keys.

---

## 4) Queue and worker command differences

Compared to current manifests, worker queue bindings were adjusted to match upstream Helm templates:

- `docfetching` queue becomes `connector_doc_fetching`
- `light` queue includes `opensearch_migration`
- `heavy` queue includes `sandbox`
- monitoring worker added with `monitoring` queue

If queue names do not match producer-side task routing, tasks can silently backlog in the wrong queue.

---

## 5) Image/version strategy differences

- **Current:** many workloads pinned to `nightly-20241004`
- **New:** pinned consistently to `v3.1.1` for Onyx components, with chart-aligned versions for dependencies (e.g., OpenSearch `3.4.0`, Vespa `8.609.39`)

This removes intra-stack version drift and is intended to improve runtime consistency.

---

## 6) Architecture and dependency differences

New manifests make these dependencies explicit:

- API and workers depend on **both** Vespa and OpenSearch paths (when enabled)
- File path uses MinIO/S3 by default (Helm model)
- Slack bot and code-interpreter become additional runtime dependencies

Operational impact:

- More complete feature parity with upstream defaults
- Higher resource footprint
- More moving parts and incident blast radius if not monitored

---

## 7) What did NOT change automatically

Even in new manifests, you still need to finalize:

- Persistent volumes for Postgres/Vespa/OpenSearch/MinIO
- Ingress/TLS strategy for production
- HPA/PDB/NetworkPolicy hardening
- Monitoring and alerting dashboards
- Secret rotation flow (Vault/ESO) mapped to new secret names/keys

---

## 8) Migration cautions

Before switching from `manifests/` to `new_manifests_values_yaml/`:

1. Prepare a mapping table old secret keys -> new secret keys.
2. Validate queue names across all producers/consumers.
3. Run staging reindex test with representative documents.
4. Canary traffic before full cutover.
5. Keep rollback manifests ready.

---

## 9) Recommended usage

- Use `new_manifests_values_yaml/` when you want closer parity with upstream Helm behavior and features.
- Keep `manifests/` for your current production baseline until staging validation is complete.

