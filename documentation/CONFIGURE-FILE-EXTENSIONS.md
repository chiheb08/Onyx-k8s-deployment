# Configuring Allowed File Extensions via Environment Variable

This guide explains how to make the list of uploadable file extensions configurable through an environment variable that can be set in the Kubernetes manifest (ConfigMap). The process involves three layers:

1. **Backend configuration** – read the variable and expose it to the upload validators.
2. **Upload validation logic** – enforce the rule when users submit files.
3. **Deployment manifests** – set the desired extensions per environment (e.g., `prod`, `dev`).

---

## 1. Add a Backend Config Variable

File: `backend/onyx/configs/app_configs.py`

```python
# Near other user-facing feature flags
DEFAULT_ALLOWED_FILE_EXTENSIONS = ["pdf", "docx", "pptx", "txt", "md"]
USER_FILE_ALLOWED_EXTENSIONS = (
    os.environ.get("USER_FILE_ALLOWED_EXTENSIONS")
    or ",".join(DEFAULT_ALLOWED_FILE_EXTENSIONS)
)
# Normalize to lowercase + strip whitespace
USER_FILE_ALLOWED_EXTENSIONS = [ext.strip().lower() for ext in USER_FILE_ALLOWED_EXTENSIONS.split(",") if ext.strip()]
```

**Notes**
- Provide a sane default list so existing deployments continue to work.
- Normalize casing because users may type `PDF` or `Pdf` in manifests.

---

## 2. Enforce the Rule During Uploads

Main entrypoint: `backend/onyx/server/features/projects/api.py`, function `upload_user_files`.

Add a helper (or reuse the existing one) before the background task is triggered:

```python
from onyx.configs.app_configs import USER_FILE_ALLOWED_EXTENSIONS


def _validate_extension(filename: str) -> None:
    if not USER_FILE_ALLOWED_EXTENSIONS:
        return  # empty list means allow everything

    ext = (filename.rsplit(".", 1)[-1]).lower() if "." in filename else ""
    if ext not in USER_FILE_ALLOWED_EXTENSIONS:
        allowed_str = ", ".join(USER_FILE_ALLOWED_EXTENSIONS)
        raise HTTPException(
            status_code=400,
            detail=f"File type '.{ext}' is not allowed. Allowed extensions: {allowed_str}",
        )
```

Inside `upload_user_files`, call `_validate_extension(upload_file.filename)` before saving the file or creating a Celery job.

Optional UI improvement: expose the list via `/api/user/projects/file/constraints` so the frontend can pre-validate before hitting the backend.

---

## 3. Wire the Variable into the Deployment Manifest

In `onyx-k8s-infrastructure/manifests/05-configmap.yaml` (or Helm chart values), add:

```yaml
data:
  # Comma-separated list, case-insensitive
  USER_FILE_ALLOWED_EXTENSIONS: "pdf,docx,pptx,txt,md"
```

If you omit the variable, the backend uses the default defined in `app_configs.py`.

### Helm or Kustomize
- **Helm**: expose it as a value (`values.yaml` → ConfigMap template).
- **ArgoCD/Kustomize**: add it to the `configMapGenerator` or patch.

### Changing per Environment
- `dev` may use `USER_FILE_ALLOWED_EXTENSIONS: "pdf,docx,csv,txt"`
- `prod` may restrict to `pdf,docx`

Apply with:
```bash
kubectl apply -f manifests/05-configmap.yaml
kubectl rollout restart deployment/api-server
```

---

## 4. (Optional) Surface the Rule in the Frontend

File: `web/src/app/chat/components/projects/ProjectContextPanel.tsx` (or dedicated upload component).

1. Fetch the allowed extensions via REST (expose a new endpoint as mentioned earlier) or embed them in `NEXT_PUBLIC_` env var.
2. Show the list near the file picker and prevent client-side selection using the HTML `accept` attribute:

```tsx
<input
  type="file"
  accept={allowedExtensions.map((ext) => `.${ext}`).join(",")}
  onChange={handleUploadChange}
/>
```

This UI step is optional but improves UX by preventing impossible uploads before they hit the backend.

---

## 5. End-to-End Test Checklist

1. **ConfigMap** updated with the desired extensions.
2. **API pod** restarted (watch `kubectl logs` for the new env var).
3. Upload a file with an allowed extension → should succeed.
4. Upload a file with a blocked extension → should return HTTP 400 with the configured message.
5. (Optional) UI shows the allowed extensions and disables unsupported files in the picker.

---

## Summary
| Layer | Action |
|-------|--------|
| Backend config | Add `USER_FILE_ALLOWED_EXTENSIONS` env parsing in `app_configs.py`. |
| Validation logic | Check extension in `upload_user_files` before saving. |
| Deployment | Set the env var in `05-configmap.yaml` (Helm/Kustomize). |
| Frontend (optional) | Show allowed extensions and pre-validate via file picker. |

Once these steps are in place, you can control which file types users may upload simply by editing the manifest and redeploying, without touching the code again.
