# Simple Guide: Make Allowed File Extensions Configurable

Follow these steps exactly. Each step shows **where** to change the code, the **old block**, and the **new block**.

---

## Architecture Snapshot – How the Environment Variable Flows

```mermaid
flowchart LR
    subgraph K8S["Kubernetes ConfigMap (05-configmap.yaml)"]
        VAR["USER_FILE_ALLOWED_EXTENSIONS_*"]
    end

    subgraph Backend["Onyx Backend"]
        CFG["allowed_extensions.py\n(lines 1-29)"]
        EXTRACT["extract_file_text.py\n(lines 40-150)"]
        API["server/features/projects/api.py\n(lines 120-230)"]
    end

    subgraph Frontend["Next.js Frontend"]
        HOOK["fetchUploadConstraints()\n(utils.ts lines 80-140)"]
        UI["ProjectContextPanel.tsx\n(lines 50-110)"]
    end

    VAR -->|env injected| CFG -->|ALLOWED_EXTENSIONS dict| EXTRACT
    CFG --> API -->|GET /api/user/uploads/constraints| HOOK --> UI
    UI -->|accept attr + validation| User
```

- **ConfigMap** defines the env vars.
- **allowed_extensions.py** reads env vars once and exports `ALLOWED_EXTENSIONS`.
- **extract_file_text.py** and `upload_user_files` import the same dict, so processing + validation stay in sync.
- **GET /api/user/uploads/constraints** returns the dict to the frontend.
- **Frontend utilities** fetch it once, then components build the `<input accept="...">` string and UI checks.

### Quick Line Reference Table

| File | Lines to edit | Purpose |
|------|---------------|---------|
| `backend/onyx/file_processing/allowed_extensions.py` | new file | Load env vars (required) and expose `ALLOWED_EXTENSIONS`. |
| `backend/onyx/file_processing/extract_file_text.py` | ~43-140 | Replace hard-coded lists + helper functions. |
| `backend/onyx/server/features/projects/api.py` | ~120-250 | Validate uploads + add optional `/uploads/constraints`. |
| `web/src/lib/utils.ts` | ~80-150 | Add `fetchUploadConstraints()` and remove `IMAGE_EXTENSIONS`. |
| `web/src/app/chat/components/projects/ProjectContextPanel.tsx` | ~40-120 | Fetch constraints and wire to `<input accept>`. |
| `manifests/05-configmap.yaml` | `data:` block | Set `USER_FILE_ALLOWED_EXTENSIONS_*` env vars. |

Use these line ranges as anchors when applying the steps below.

---

## Step 1 – Create a Shared Extension List (Backend)

**File:** `backend/onyx/file_processing/allowed_extensions.py` (new file)

```python
# NEW FILE CONTENT (all values come from env)
import os

def _load_required(key: str) -> list[str]:
    raw = os.environ.get(key)
    if not raw:
        raise RuntimeError(
            f"{key} must be set (comma-separated list). Define it in 05-configmap.yaml."
        )
    extensions = []
    for part in raw.split(","):
        cleaned = part.strip().lower()
        if not cleaned:
            continue
        if not cleaned.startswith("."):
            cleaned = "." + cleaned
        extensions.append(cleaned)
    if not extensions:
        raise RuntimeError(f"{key} resolved to an empty list. Provide at least one extension.")
    return extensions


ALLOWED_EXTENSIONS = {
    "plain_text": _load_required("USER_FILE_ALLOWED_EXTENSIONS_PLAIN"),
    "document": _load_required("USER_FILE_ALLOWED_EXTENSIONS_DOC"),
    "image": _load_required("USER_FILE_ALLOWED_EXTENSIONS_IMG"),
}

ALLOWED_EXTENSIONS["all"] = sorted(
    set(
        ALLOWED_EXTENSIONS["plain_text"]
        + ALLOWED_EXTENSIONS["document"]
        + ALLOWED_EXTENSIONS["image"]
    )
)
```

---

## Step 2 – Update Extractor to Use the Shared List

**File:** `backend/onyx/file_processing/extract_file_text.py`

### 2.1 Replace the hard-coded lists at the top

```diff
-ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS = [".txt", ...]
-ACCEPTED_DOCUMENT_FILE_EXTENSIONS = [".pdf", ...]
-ACCEPTED_IMAGE_FILE_EXTENSIONS = [".png", ...]
-ALL_ACCEPTED_FILE_EXTENSIONS = (
-    ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS
-    + ACCEPTED_DOCUMENT_FILE_EXTENSIONS
-    + ACCEPTED_IMAGE_FILE_EXTENSIONS
-)
+from onyx.file_processing.allowed_extensions import ALLOWED_EXTENSIONS
```

### 2.2 Update helper functions

```diff
-def is_text_file_extension(file_name: str) -> bool:
-    return any(file_name.endswith(ext) for ext in ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS)
+def is_text_file_extension(file_name: str) -> bool:
+    lowered = file_name.lower()
+    return any(lowered.endswith(ext) for ext in ALLOWED_EXTENSIONS["plain_text"])
```

```diff
-def is_accepted_file_ext(ext: str, ext_type: OnyxExtensionType) -> bool:
-    if ext_type & OnyxExtensionType.Plain:
-        if ext in ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS:
-            return True
-    ...
-    return False
+def is_accepted_file_ext(ext: str, ext_type: OnyxExtensionType) -> bool:
+    if ext_type & OnyxExtensionType.Plain and ext in ALLOWED_EXTENSIONS["plain_text"]:
+        return True
+    if ext_type & OnyxExtensionType.Document and ext in ALLOWED_EXTENSIONS["document"]:
+        return True
+    if ext_type & OnyxExtensionType.Multimedia and ext in ALLOWED_EXTENSIONS["image"]:
+        return True
+    return False
```

### 2.3 Whenever you need the full list

```diff
-ALL_ACCEPTED_FILE_EXTENSIONS
+ALLOWED_EXTENSIONS["all"]
```

---

## Step 3 – Validate Uploads Against the Same List

**File:** `backend/onyx/server/features/projects/api.py`

Locate `_validate_extension` (or create it right above `upload_user_files`).

```diff
-from fastapi import HTTPException
-...
-def _validate_extension(filename: str) -> None:
-    # existing logic
+from fastapi import HTTPException
+from onyx.file_processing.allowed_extensions import ALLOWED_EXTENSIONS
+
+
+def _validate_extension(filename: str) -> None:
+    ext = f".{filename.rsplit('.', 1)[-1].lower()}" if "." in filename else ""
+    if ext not in ALLOWED_EXTENSIONS["all"]:
+        allowed_str = ", ".join(ALLOWED_EXTENSIONS["all"])
+        raise HTTPException(
+            status_code=400,
+            detail=f"File type '{ext or 'unknown'}' is not allowed. Allowed: {allowed_str}",
+        )
```

Right after reading each upload:

```diff
 for upload_file in files:
+    _validate_extension(upload_file.filename)
     # continue handling
```

---

## Step 4 – Optional: Expose the List to the Frontend

**File:** `backend/onyx/server/features/projects/api.py`

```python
@router.get("/uploads/constraints")
def get_upload_constraints():
    return ALLOWED_EXTENSIONS
```

This endpoint simply returns the dictionary from Step 1.

---

## Step 5 – Update the Frontend Utilities (Super Detailed)

You will touch two files:

1. `web/src/lib/utils.ts` – shared helper functions.
2. `web/src/app/chat/components/projects/ProjectContextPanel.tsx` – the UI that draws the file picker.

None of this requires deep React knowledge. Follow the copy/paste blocks exactly.

### 5.1 Replace the hard-coded image list

**File:** `web/src/lib/utils.ts`

Find the block near the top that looks like:

```ts
export const IMAGE_EXTENSIONS = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp"] as const;
```

Delete that entire block and replace it with the new code below.

**New code (place in the same spot):**

```ts
// --- Upload constraints fetched from backend -----------------------
export type UploadConstraints = {
  plain_text: string[];
  document: string[];
  image: string[];
  all: string[];
};

let cachedConstraints: UploadConstraints | null = null;

export async function fetchUploadConstraints(): Promise<UploadConstraints> {
  if (cachedConstraints) {
    return cachedConstraints;
  }

  const response = await fetch("/api/user/uploads/constraints");
  if (!response.ok) {
    throw new Error("Failed to load upload constraints");
  }

  cachedConstraints = (await response.json()) as UploadConstraints;
  return cachedConstraints;
}
// -------------------------------------------------------------------
```

This gives us a reusable helper to retrieve the allowed extensions from the backend endpoint you created earlier.

### 5.2 Use the helper inside the upload UI

**File:** `web/src/app/chat/components/projects/ProjectContextPanel.tsx`

1. **Add imports at the top of the file**

   Look for the other imports (React, hooks, etc.) and add the new ones:

   ```diff
   +import { useEffect, useState } from "react";
   +import { fetchUploadConstraints, UploadConstraints } from "@/lib/utils";
   ```

2. **Add state + effect near the beginning of the component**

   You will find something like:

   ```ts
   export function ProjectContextPanel(props: ProjectContextPanelProps) {
     const [showUploader, setShowUploader] = useState(false);
     // ...other hooks...
   ```

   Insert the new block **right after** the existing `useState` / `useMemo` hooks, before any `useEffect` already there. Use the old/new format below.

   **Old:**
   ```ts
   const [showUploader, setShowUploader] = useState(false);
   const projectFiles = useMemo(/* ... */);
   ```

   **New:**
   ```ts
   const [showUploader, setShowUploader] = useState(false);
   const projectFiles = useMemo(/* ... */);

   const [uploadConstraints, setUploadConstraints] = useState<UploadConstraints | null>(null);

   useEffect(() => {
     fetchUploadConstraints()
       .then(setUploadConstraints)
       .catch(() => {
         setUploadConstraints({
           plain_text: [".txt", ".md"],
           document: [".pdf", ".docx"],
           image: [".png", ".jpg"],
           all: [".txt", ".md", ".pdf", ".docx", ".png", ".jpg"],
         });
       });
   }, []);
   ```

3. **Update the `<input type="file">` element**

   In this component the file input is provided by `react-dropzone`. Scroll toward the bottom until you see the comment:

   ```tsx
   {/* Hidden input just to satisfy dropzone contract; we rely on FilePicker for clicks */}
   <input {...getInputProps()} />
   ```

   Replace that line with the following so we inject the `accept` list while keeping all the dropzone props:

   ```tsx
   <input
     {...getInputProps({
       accept: uploadConstraints?.all.join(","),
     })}
     data-testid="project-context-file-input"
   />
   ```

   The dropzone spread keeps the drag/drop behavior intact, and the `accept` option enforces the allowed extensions. If the constraints haven’t loaded yet, `accept` will be `undefined`, which is fine (browser falls back to any file).

4. **Optional helper text (highly recommended)**

   Right under the input, you can show the list to the user:

   ```tsx
   {uploadConstraints && (
     <p className="text-xs text-text-03 mt-1">
       Allowed: {uploadConstraints.all.join(", ")}
     </p>
   )}
   ```

### Summary of frontend edits

| File | Old | New |
|------|-----|-----|
| `web/src/lib/utils.ts` | `IMAGE_EXTENSIONS` constant | `fetchUploadConstraints()` helper |
| `ProjectContextPanel.tsx` | No knowledge of allowed extensions | Fetch constraints via hook, set `accept`, show helper text |

Once this is done, your UI will automatically match whatever is configured in the backend env vars. No manual sync needed. Guardrails:
- If the endpoint fails, the fallback list keeps the UI usable.
- If you later add this logic to other components (drag/drop, admin upload, etc.) just reuse `fetchUploadConstraints()`.

---

## Step 6 – Wire the Environment Variables

**File:** `manifests/05-configmap.yaml`

All three variables below are required because the backend has **no code defaults**.

```yaml
data:
  USER_FILE_ALLOWED_EXTENSIONS_PLAIN: "txt,md,mdx,log,csv"
  USER_FILE_ALLOWED_EXTENSIONS_DOC: "pdf,docx,pptx,xlsx,eml,epub,html"
  USER_FILE_ALLOWED_EXTENSIONS_IMG: "png,jpg,jpeg,webp"
```

Apply and restart:

```bash
kubectl apply -f manifests/05-configmap.yaml
kubectl rollout restart deployment/api-server
```

---

## Done!

Now the backend, frontend, and manifests all point to the same, configurable list of extensions. Update the ConfigMap later to add/remove extensions without touching the code again.
