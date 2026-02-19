# Troubleshooting: set application log level (api-server + celery) on OpenShift

If you want **more application logs** (e.g. `debug`) from Onyx backend pods, set the Python log level.

## Which pods this affects

Setting `LOG_LEVEL` affects **Python** services:

- `api-server`
- `celery-beat`
- all `celery-worker-*`

It does **not** control the Next.js `web-server` logs (those are Node/Next logs).

## How to set it (recommended: ConfigMap)

In this repo, the shared ConfigMap is `manifests/05-configmap.yaml` (`onyx-config`).
Add or change:

```yaml
data:
  LOG_LEVEL: "debug"
```

Supported values: `debug`, `info`, `notice`, `warning`, `error`, `critical`.

## After changing it

Once ArgoCD syncs the ConfigMap:

- Restart rollouts for `api-server` and your celery deployments (or wait for your deployment strategy to pick it up).

In OpenShift UI:

- Workloads → Deployments → select deployment → Actions → Restart rollout

## Where to view logs

OpenShift Console → Workloads → Pods → select pod → Logs.

