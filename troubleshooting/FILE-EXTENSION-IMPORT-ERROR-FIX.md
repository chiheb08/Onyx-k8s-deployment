# Fix: ImportError for ACCEPTED_*_FILE_EXTENSIONS

## The Error

```
ImportError: cannot import name 'ACCEPTED_IMAGE_FILE_EXTENSIONS' from 'onyx.file_processing.extract_file_text'
ImportError: cannot import name 'ALL_ACCEPTED_FILE_EXTENSIONS' from 'onyx.file_processing.extract_file_text'
ImportError: cannot import name 'ACCEPTED_DOCUMENT_FILE_EXTENSIONS' from 'onyx.file_processing.extract_file_text'
```

---

## ALL Files That Need Updating

| File | Old Imports |
|------|-------------|
| `backend/onyx/server/features/projects/projects_file_utils.py` | `ACCEPTED_IMAGE_FILE_EXTENSIONS`, `ALL_ACCEPTED_FILE_EXTENSIONS` |
| `backend/onyx/connectors/google_drive/doc_conversion.py` | `ALL_ACCEPTED_FILE_EXTENSIONS` |
| `backend/onyx/connectors/sharepoint/connector.py` | `ACCEPTED_IMAGE_FILE_EXTENSIONS` |
| `backend/onyx/connectors/highspot/connector.py` | `ACCEPTED_DOCUMENT_FILE_EXTENSIONS`, `ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS` |
| `backend/tests/daily/connectors/blob/test_blob_connector.py` | `ACCEPTED_DOCUMENT_FILE_EXTENSIONS`, `ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS` |

---

## Mapping Table

| Old Constant | New Equivalent |
|--------------|----------------|
| `ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS` | `ALLOWED_EXTENSIONS["plain_text"]` |
| `ACCEPTED_DOCUMENT_FILE_EXTENSIONS` | `ALLOWED_EXTENSIONS["document"]` |
| `ACCEPTED_IMAGE_FILE_EXTENSIONS` | `ALLOWED_EXTENSIONS["image"]` |
| `ALL_ACCEPTED_FILE_EXTENSIONS` | `ALLOWED_EXTENSIONS["all"]` |

---

## Fix for Each File

---

### 1. `backend/onyx/server/features/projects/projects_file_utils.py`

**Line 11-12 OLD:**
```python
from onyx.file_processing.extract_file_text import ACCEPTED_IMAGE_FILE_EXTENSIONS
from onyx.file_processing.extract_file_text import ALL_ACCEPTED_FILE_EXTENSIONS
```

**Line 11 NEW:**
```python
from onyx.file_processing.allowed_extensions import ALLOWED_EXTENSIONS
```

**Line 135 OLD:**
```python
if extension in ACCEPTED_IMAGE_FILE_EXTENSIONS:
```

**Line 135 NEW:**
```python
if extension in ALLOWED_EXTENSIONS["image"]:
```

**Lines 153-156 OLD:**
```python
if (
    extension in ALL_ACCEPTED_FILE_EXTENSIONS
    and extension not in ACCEPTED_IMAGE_FILE_EXTENSIONS
):
```

**Lines 153-156 NEW:**
```python
if (
    extension in ALLOWED_EXTENSIONS["all"]
    and extension not in ALLOWED_EXTENSIONS["image"]
):
```

---

### 2. `backend/onyx/connectors/google_drive/doc_conversion.py`

**Line 32 OLD:**
```python
from onyx.file_processing.extract_file_text import ALL_ACCEPTED_FILE_EXTENSIONS
```

**Line 32 NEW:**
```python
from onyx.file_processing.allowed_extensions import ALLOWED_EXTENSIONS
```

**Then replace all occurrences of:**
```python
ALL_ACCEPTED_FILE_EXTENSIONS
```

**With:**
```python
ALLOWED_EXTENSIONS["all"]
```

---

### 3. `backend/onyx/connectors/sharepoint/connector.py`

**Line 57 OLD:**
```python
from onyx.file_processing.extract_file_text import ACCEPTED_IMAGE_FILE_EXTENSIONS
```

**Line 57 NEW:**
```python
from onyx.file_processing.allowed_extensions import ALLOWED_EXTENSIONS
```

**Then replace all occurrences of:**
```python
ACCEPTED_IMAGE_FILE_EXTENSIONS
```

**With:**
```python
ALLOWED_EXTENSIONS["image"]
```

---

### 4. `backend/onyx/connectors/highspot/connector.py`

**Lines 26-27 OLD:**
```python
from onyx.file_processing.extract_file_text import ACCEPTED_DOCUMENT_FILE_EXTENSIONS
from onyx.file_processing.extract_file_text import ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS
```

**Line 26 NEW (delete line 27):**
```python
from onyx.file_processing.allowed_extensions import ALLOWED_EXTENSIONS
```

**Then replace:**
- `ACCEPTED_DOCUMENT_FILE_EXTENSIONS` → `ALLOWED_EXTENSIONS["document"]`
- `ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS` → `ALLOWED_EXTENSIONS["plain_text"]`

---

### 5. `backend/tests/daily/connectors/blob/test_blob_connector.py`

**Lines 14-15 OLD:**
```python
from onyx.file_processing.extract_file_text import ACCEPTED_DOCUMENT_FILE_EXTENSIONS
from onyx.file_processing.extract_file_text import ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS
```

**Line 14 NEW (delete line 15):**
```python
from onyx.file_processing.allowed_extensions import ALLOWED_EXTENSIONS
```

**Then replace:**
- `ACCEPTED_DOCUMENT_FILE_EXTENSIONS` → `ALLOWED_EXTENSIONS["document"]`
- `ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS` → `ALLOWED_EXTENSIONS["plain_text"]`

---

## EASIEST FIX: Restore Old Constants

If you don't want to update all these files, just **add the constants back** to `extract_file_text.py`:

**File:** `backend/onyx/file_processing/extract_file_text.py`

**Add these lines around line 43 (after the imports):**

```python
ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS = [
    ".txt",
    ".md",
    ".mdx",
    ".conf",
    ".log",
    ".json",
    ".csv",
    ".tsv",
    ".xml",
    ".yml",
    ".yaml",
    ".sql",
]

ACCEPTED_DOCUMENT_FILE_EXTENSIONS = [
    ".pdf",
    ".docx",
    ".pptx",
    ".xlsx",
    ".eml",
    ".epub",
    ".html",
]

ACCEPTED_IMAGE_FILE_EXTENSIONS = [
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
]

ALL_ACCEPTED_FILE_EXTENSIONS = (
    ACCEPTED_PLAIN_TEXT_FILE_EXTENSIONS
    + ACCEPTED_DOCUMENT_FILE_EXTENSIONS
    + ACCEPTED_IMAGE_FILE_EXTENSIONS
)
```

**This is the fastest fix - no other files need to change!**

---

## Summary

**Two options:**

| Option | What to do | Files to change |
|--------|------------|-----------------|
| **A (Easy)** | Add constants back to `extract_file_text.py` | 1 file |
| **B (Full)** | Update all imports to use `ALLOWED_EXTENSIONS` | 5 files |

**Recommendation:** Use Option A (Easy) for now. You can always do the full migration later.
