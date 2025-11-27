# Fix: ImportError for ACCEPTED_IMAGE_FILE_EXTENSIONS

## The Error

```
ImportError: cannot import name 'ACCEPTED_IMAGE_FILE_EXTENSIONS' from 'onyx.file_processing.extract_file_text'
```

---

## Why This Happens

If you applied the **file extension guide** changes (replacing hard-coded lists with environment variables), you removed the constants from `extract_file_text.py`.

But other files still import those old constants, causing this error.

---

## Files That Need Updating

Run this command to find all files importing the old constants:

```bash
grep -rn "ACCEPTED_IMAGE_FILE_EXTENSIONS\|ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS\|ACCEPTED_DOCUMENT_FILE_EXTENSIONS\|ALL_ACCEPTED_FILE_EXTENSIONS" backend/
```

### Known files to update:

| File | Line | Old Import |
|------|------|------------|
| `backend/onyx/server/features/projects/projects_file_utils.py` | ~12 | `ACCEPTED_IMAGE_FILE_EXTENSIONS` |

---

## How to Fix Each File

### Step 1: Change the import

**Old:**
```python
from onyx.file_processing.extract_file_text import ACCEPTED_IMAGE_FILE_EXTENSIONS
```

**New:**
```python
from onyx.file_processing.allowed_extensions import ALLOWED_EXTENSIONS
```

### Step 2: Update the usage

**Old:**
```python
if ext in ACCEPTED_IMAGE_FILE_EXTENSIONS:
    # do something
```

**New:**
```python
if ext in ALLOWED_EXTENSIONS["image"]:
    # do something
```

---

## Mapping Table

| Old Constant | New Equivalent |
|--------------|----------------|
| `ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS` | `ALLOWED_EXTENSIONS["plain_text"]` |
| `ACCEPTED_DOCUMENT_FILE_EXTENSIONS` | `ALLOWED_EXTENSIONS["document"]` |
| `ACCEPTED_IMAGE_FILE_EXTENSIONS` | `ALLOWED_EXTENSIONS["image"]` |
| `ALL_ACCEPTED_FILE_EXTENSIONS` | `ALLOWED_EXTENSIONS["all"]` |

---

## Example Fix for `projects_file_utils.py`

**File:** `backend/onyx/server/features/projects/projects_file_utils.py`

### Old (around line 12):

```python
from onyx.file_processing.extract_file_text import ACCEPTED_IMAGE_FILE_EXTENSIONS
```

### New:

```python
from onyx.file_processing.allowed_extensions import ALLOWED_EXTENSIONS
```

### Then find any usage like:

```python
# Old
if extension in ACCEPTED_IMAGE_FILE_EXTENSIONS:

# New
if extension in ALLOWED_EXTENSIONS["image"]:
```

---

## Complete Checklist

1. [ ] Create `backend/onyx/file_processing/allowed_extensions.py` (if not done)
2. [ ] Update `backend/onyx/file_processing/extract_file_text.py` (remove old constants)
3. [ ] Update `backend/onyx/server/features/projects/projects_file_utils.py`
4. [ ] Search for any other files importing old constants
5. [ ] Update ConfigMap with required environment variables
6. [ ] Restart API server

---

## Prevention

When removing constants from a file, always search the entire codebase for imports:

```bash
grep -rn "from onyx.file_processing.extract_file_text import" backend/
```

This shows all files that import from that module, so you can update them all at once.

---

## Quick Fix (If You Don't Want Env Vars Yet)

If you just want to restore the old behavior temporarily, add the constants back to `extract_file_text.py`:

```python
# Add these back at the top of extract_file_text.py (around line 43)
ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS = [".txt", ".md", ".mdx", ".conf", ".log", ".json", ".csv", ".tsv", ".xml", ".yml", ".yaml", ".sql"]
ACCEPTED_DOCUMENT_FILE_EXTENSIONS = [".pdf", ".docx", ".pptx", ".xlsx", ".eml", ".epub", ".html"]
ACCEPTED_IMAGE_FILE_EXTENSIONS = [".png", ".jpg", ".jpeg", ".webp"]
ALL_ACCEPTED_FILE_EXTENSIONS = (
    ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS
    + ACCEPTED_DOCUMENT_FILE_EXTENSIONS
    + ACCEPTED_IMAGE_FILE_EXTENSIONS
)
```

This restores the old behavior without needing environment variables.

