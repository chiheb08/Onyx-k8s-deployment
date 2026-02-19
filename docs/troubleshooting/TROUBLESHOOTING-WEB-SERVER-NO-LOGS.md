# Troubleshooting: web-server pod shows “no logs” (Onyx / Next.js)

Onyx `web-server` runs a **Next.js** application. Its logging differs from the Python backend:

- The backend uses `LOG_LEVEL` (Python logging).
- The Next.js server is a **Node.js** process and typically logs **very little** in production unless:
  - it encounters errors, or
  - you enable debug logging.

---

## 1) First check: is traffic actually reaching the web-server?

If `web-server` receives no requests, it may legitimately produce no logs.
Verify:

- the service is reachable
- nginx/route points to the correct service/port

---

## 2) Enable verbose Next.js logs (recommended for debugging)

Next.js uses Node-style debug logging. Set:

- `DEBUG=next:*`

In this repo, the manifest `manifests/08-web-server.yaml` supports enabling it via env vars.

---

## 3) What to set in the Deployment

Add these env vars under the `web-server` container:

```yaml
env:
  - name: DEBUG
    value: "next:*"
  - name: NEXT_TELEMETRY_DISABLED
    value: "1"
```

Notes:

- `DEBUG=next:*` can be noisy. If it’s too much, narrow it (example: `next:server*`).
- `NEXT_TELEMETRY_DISABLED=1` is optional.

---

## 4) Where to view the logs in OpenShift UI

- OpenShift Console → Workloads → Pods → `<web-server pod>` → Logs

Make sure you are viewing logs from the correct container if the pod has multiple containers.

