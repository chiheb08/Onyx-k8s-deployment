# Configuring Allowed File Extensions (Old vs New Approach)

This document expands the original high-level notes into **step-by-step instructions** that cover the entire stack—backend, API, frontend, and Kubernetes manifests—while comparing the **current (old) hard-coded approach** against the **new configurable approach** you requested.

We focus on two files you pointed out:

- `backend/onyx/file_processing/extract_file_text.py` – currently hard-codes the allowed extensions lists.
- `web/src/lib/utils.ts` – hard-codes image extensions in the frontend.

---

## 0. Before You Start – Understand the Old Layout

| Layer | Old Behaviors |
|-------|---------------|
| Backend extraction (`extract_file_text.py`) | Three hard-coded lists: `ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS`, `ACCEPTED_DOCUMENT_FILE_EXTENSIONS`, `ACCEPTED_IMAGE_FILE_EXTENSIONS`. Helpers like `is_accepted_file_ext` and `is_text_file_extension` depend on them. |
| Backend validation (`upload_user_files`) | Uses its own logic/check; difficult to sync with extraction lists. |
| Frontend utilities (`web/src/lib/utils.ts`) | Hard-coded `IMAGE_EXTENSIONS` array used by multiple components, independent of backend lists. |
| Deployment | No knob to change extensions without editing code. |

**Pain points:** multiple sources of truth, code edits required per environment, frontend can disagree with backend.

---

## 1. New Architecture Overview

| Layer | New Responsibilities |
|-------|----------------------|
| Backend config | Read `USER_FILE_ALLOWED_EXTENSIONS` (and optional subtype env vars) from environment/ConfigMap. Provide defaults. |
| Shared module | Export normalized extension arrays so both `extract_file_text.py` and upload validators reuse them. |
| API endpoint | Offer `GET /api/user/uploads/constraints` returning the authoritative list for the frontend. |
| Frontend | Fetch constraints once (e.g., with SWR hook) and use them everywhere (`accept` attribute, tooltips, `isImageFile` logic). No more local enums. |
| Deployment | Set env vars in `05-configmap.yaml` or Helm values to adjust per environment. |

---

## 2. Backend Changes (Step by Step)

### 2.1 Centralize Extension Lists

**Old (partial extract from `extract_file_text.py`):**

```python
ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS = [".txt", ".md", ".mdx", ...]
ACCEPTED_DOCUMENT_FILE_EXTENSIONS = [".pdf", ".docx", ...]
ACCEPTED_IMAGE_FILE_EXTENSIONS = [".png", ".jpg", ...]
```

**New (example `backend/onyx/file_processing/allowed_extensions.py`):**

```python
import os

DEFAULT_FILE_EXTENSIONS = {
    "plain_text": [".txt", ".md", ".mdx", ".log", ".csv"],
    "document": [".pdf", ".docx", ".pptx", ".xlsx", ".eml", ".epub", ".html"],
    "image": [".png", ".jpg", ".jpeg", ".webp"],
}

def _read_env(key: str, fallback: list[str]) -> list[str]:
    raw = os.environ.get(key)
    if not raw:
        return fallback
    return [
        ext.lower() if ext.startswith(".") else f".{ext.lower()}"
        for ext in raw.split(",")
        if ext.strip()
    ]

ALLOWED_EXTENSIONS = {
    "plain_text": _read_env("USER_FILE_ALLOWED_EXTENSIONS_PLAIN", DEFAULT_FILE_EXTENSIONS["plain_text"]),
    "document": _read_env("USER_FILE_ALLOWED_EXTENSIONS_DOC", DEFAULT_FILE_EXTENSIONS["document"]),
    "image": _read_env("USER_FILE_ALLOWED_EXTENSIONS_IMG", DEFAULT_FILE_EXTENSIONS["image"]),
}

ALLOWED_EXTENSIONS["all"] = sorted(
    set(ALLOWED_EXTENSIONS["plain_text"] + ALLOWED_EXTENSIONS["document"] + ALLOWED_EXTENSIONS["image"])
)
```

- You can keep a single env var (`USER_FILE_ALLOWED_EXTENSIONS`) if you prefer; the snippet above shows per-category variables for flexibility.
- Normalize everything to `.lower()` with leading dots so the rest of the code stays consistent.

### 2.2 Update `extract_file_text.py`

1. Replace the old lists with imports:
   ```python
   from onyx.file_processing.allowed_extensions import ALLOWED_EXTENSIONS
   ```
2. Adjust helpers like `is_text_file_extension`:
   ```python
   def is_text_file_extension(file_name: str) -> bool:
       return any(file_name.lower().endswith(ext) for ext in ALLOWED_EXTENSIONS["plain_text"])
   ```
3. Update `is_accepted_file_ext` to reference `ALLOWED_EXTENSIONS`.

This ensures extraction logic always respects the ConfigMap-driven list.

### 2.3 Update Upload Validation (`backend/onyx/server/features/projects/api.py`)

**Old (pseudocode):**
```python
if file_extension not in SOME_LOCAL_LIST:
    raise HTTPException(...)
```

**New:**
```python
from onyx.file_processing.allowed_extensions import ALLOWED_EXTENSIONS

def _validate_extension(filename: str) -> None:
    ext = f".{filename.rsplit('.', 1)[-1].lower()}" if "." in filename else ""
    if ext not in ALLOWED_EXTENSIONS["all"]:
        allowed_str = ", ".join(ALLOWED_EXTENSIONS["all"])
        raise HTTPException(
            status_code=400,
            detail=f"File type '{ext or 'Unknown'}' is not allowed. Allowed extensions: {allowed_str}",
        )
```

Call `_validate_extension(upload_file.filename)` immediately after reading the upload stream.

### 2.4 Optional – Add a Read-Only API

File: `backend/onyx/server/features/projects/api.py`

```python
@router.get("/uploads/constraints", response_model=UploadConstraintsResponse)
async def get_upload_constraints() -> UploadConstraintsResponse:
    return UploadConstraintsResponse(
        plain_text=ALLOWED_EXTENSIONS["plain_text"],
        document=ALLOWED_EXTENSIONS["document"],
        image=ALLOWED_EXTENSIONS["image"],
        all=ALLOWED_EXTENSIONS["all"],
    )
```

Response model example:
```python
class UploadConstraintsResponse(BaseModel):
    plain_text: list[str]
    document: list[str]
    image: list[str]
    all: list[str]
```

This gives the frontend a single place to fetch the rule set.

---

## 3. Frontend Changes (Step by Step)

### 3.1 Replace Hard-Coded Arrays in `web/src/lib/utils.ts`

**Old:**
```ts
export const IMAGE_EXTENSIONS = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp"] as const;
```

**New Approach:**
1. Create a hook or service (e.g. `web/src/app/chat/hooks/useUploadConstraints.ts`) that fetches the backend endpoint once and caches it.
   ```ts
   import useSWR from "swr";

   export function useUploadConstraints() {
     return useSWR("/api/user/uploads/constraints", fetcher);
   }
   ```
2. Update `isImageExtension` to use the fetched data:
   ```ts
   export function isImageExtension(extension: string | null | undefined, constraints?: UploadConstraints): boolean {
     if (!extension || !constraints) return false;
     return constraints.image.some((ext) => extension.toLowerCase().endsWith(ext.replace(".", "")));
   }
   ```
3. Components like `ProjectContextPanel` and `FilesList` consume the hook:
   ```tsx
   const { data: uploadConstraints } = useUploadConstraints();
   const acceptAttr = useMemo(
     () => uploadConstraints?.all.join(",") ?? ".pdf,.docx,.txt",
     [uploadConstraints]
   );

   <input type="file" accept={acceptAttr} ... />
   ```

**Result:** any change in the ConfigMap automatically propagates to the UI without code edits.

---

## 4. Deployment Steps (ConfigMap / Helm)

In `manifests/05-configmap.yaml`:

```yaml
data:
  # Single list (simple setup)
  USER_FILE_ALLOWED_EXTENSIONS: "pdf,docx,pptx,txt,md"

  # Optional per-category overrides
  USER_FILE_ALLOWED_EXTENSIONS_PLAIN: "txt,md,mdx,log,csv"
  USER_FILE_ALLOWED_EXTENSIONS_DOC: "pdf,docx,pptx,xlsx,eml,epub,html"
  USER_FILE_ALLOWED_EXTENSIONS_IMG: "png,jpg,jpeg,webp"
```

Apply and restart API deployment:

```bash
kubectl apply -f manifests/05-configmap.yaml
kubectl rollout restart deployment/api-server
```

For Helm/Kustomize, bubble these values through `values.yaml` or `configMapGenerator`.

---

## 5. End-to-End Validation Checklist

1. **Backend unit test** – ensure `_validate_extension` rejects unexpected formats and accepts configured ones.
2. **API manual test** – `curl /api/user/uploads/constraints` should match ConfigMap.
3. **Frontend** – upload dialog only shows allowed extensions; selecting a disallowed file triggers instant error tooltip.
4. **Runtime** – uploading approved files succeeds; disallowed ones return `400` with the server-provided message.
5. **Change management** – modify the ConfigMap to add/remove `csv`, redeploy, verify UI and backend reflect the change without code modifications.

---

## 6. Quick Reference Table (Old vs New)

| Area | Old | New |
|------|-----|-----|
| Backend lists | Hard-coded arrays in `extract_file_text.py` | Shared module reading env vars; used by extraction + validation |
| Frontend | `IMAGE_EXTENSIONS` constant in `utils.ts` | Fetch constraints from backend; no hard-coding |
| Config | None | ConfigMap env vars (`USER_FILE_ALLOWED_EXTENSIONS*`) |
| Sync effort | Manual edits in multiple files | Single source of truth; redeploy only |

---

Once these steps are implemented, adding or removing file extensions is as easy as editing the manifest and restarting the API pods—no more code tours through backend and frontend files. Feel free to adapt the naming of the env vars or endpoint paths, but keep the “single source of truth” principle intact.

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
