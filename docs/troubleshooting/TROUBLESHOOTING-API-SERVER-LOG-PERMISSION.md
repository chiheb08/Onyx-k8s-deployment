# Troubleshooting: API server fails with `Permission denied: /var/log/onyx/...`

## Symptoms

You see a crash like:

- `PermissionError: [Errno 13] Permission denied: '/var/log/onyx/onyx_debug.log'`

## Why this happens (simple explanation)

- Onyx always writes logs to **stdout/stderr** (so `oc logs` works).
- **Additionally**, Onyx may try to write **rotating log files** under:
  - `/var/log/onyx/<something>_debug.log`
  - `/var/log/onyx/<something>_info.log`
  - `/var/log/onyx/<something>_notice.log`
- It decides “I’m inside a container, use `/var/log/onyx`” by checking the env var:
  - **`DANSWER_RUNNING_IN_DOCKER`**
    - If it is **`"true"`**, Onyx uses `/var/log/onyx/...`
    - If it is **not `"true"`**, Onyx uses `./log/...` (or just stdout in many setups)

On OpenShift, pods often run as a **random user ID**, and `/var/log/onyx` is **not writable** by that user unless you explicitly allow it. That’s why the app fails when it tries to create `onyx_debug.log`.

## Where to look

### 1) In your Deployment YAML (manifests)

Check:

- `spec.template.spec.containers[].env` and `envFrom`
- `spec.template.spec.initContainers[].env` and `envFrom` (migration container)

You’re looking for:

- `DANSWER_RUNNING_IN_DOCKER`

If you don’t see it, it may be:

- set in the **Dockerfile** (`ENV DANSWER_RUNNING_IN_DOCKER=true`), or
- injected from a **ConfigMap/Secret** referenced via `envFrom`.

### 2) In the running pod (most reliable)

```bash
oc exec -n <NAMESPACE> -it deploy/api-server -- sh -lc 'printenv | egrep "DANSWER_RUNNING_IN_DOCKER|DEV_LOGGING_ENABLED|LOG_FILE_NAME"'
```

## Fix 1 (recommended on OpenShift): disable “container file logs”, use stdout only

Add this env var override to your API container (and migration initContainer if needed):

```yaml
env:
  - name: DANSWER_RUNNING_IN_DOCKER
    value: "false"
```

Result:

- Onyx stops trying to write to `/var/log/onyx/*`
- You still get logs via `oc logs`

## Fix 2: keep file logs, but make `/var/log/onyx` writable

Pick **one** of these approaches:

### Option A: Mount a writable volume at `/var/log/onyx`

- Add an `emptyDir` volume
- Mount it to `/var/log/onyx`
- (If needed) add an initContainer that `chmod`s it

This is the most Kubernetes-native fix.

### Option B: Change permissions in your custom image

If you build your own image, ensure `/var/log/onyx` is writable by the runtime user.
The simplest (but broad) approach is:

```dockerfile
USER root
RUN mkdir -p /var/log/onyx && chmod -R 0777 /var/log/onyx
```

> Note: If `/var/log/onyx` is a **volume mount**, Dockerfile permissions won’t matter (the mount replaces the directory). Use “Option A” in that case.


