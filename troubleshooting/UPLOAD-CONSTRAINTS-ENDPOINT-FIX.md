# Fix: RuntimeError for get_upload_constraints Endpoint

## The Error

```
RuntimeError: Did not find user dependency in private route - APIRoute(path='/user/projects/uploads/constraints', name='get_upload_constraints', methods=['GET'])
```

---

## Why This Happens

The `/uploads/constraints` endpoint was added without the required `user` dependency. In Onyx, all routes under `/user/` must include user authentication.

---

## The Fix

**File:** `backend/onyx/server/features/projects/api.py`

Find the endpoint you added:

**OLD (Wrong):**
```python
@router.get("/uploads/constraints")
def get_upload_constraints():
    return ALLOWED_EXTENSIONS
```

**NEW (Correct):**
```python
from onyx.auth.users import current_user

@router.get("/uploads/constraints")
def get_upload_constraints(
    user: User | None = Depends(current_user),
) -> dict:
    """Return allowed file extensions for uploads."""
    return ALLOWED_EXTENSIONS
```

---

## Complete Example

Here's the full corrected endpoint:

```python
from onyx.auth.users import current_user
from onyx.db.models import User
from fastapi import Depends

@router.get("/uploads/constraints")
def get_upload_constraints(
    user: User | None = Depends(current_user),
) -> dict:
    """Return allowed file extensions for uploads.
    
    Returns a dictionary with keys:
    - plain_text: list of plain text extensions
    - document: list of document extensions  
    - image: list of image extensions
    - all: combined list of all extensions
    """
    return ALLOWED_EXTENSIONS
```

---

## Alternative: Remove the Endpoint

If you don't need the frontend to fetch constraints dynamically, simply **delete the endpoint** from `api.py`:

```python
# DELETE THIS ENTIRE BLOCK:
@router.get("/uploads/constraints")
def get_upload_constraints():
    return ALLOWED_EXTENSIONS
```

The frontend will use its fallback list instead.

---

## Quick Summary

| Problem | Solution |
|---------|----------|
| Missing `user` dependency | Add `user: User \| None = Depends(current_user)` parameter |
| Or just remove the endpoint | Delete the `@router.get("/uploads/constraints")` block |

---

## Recommendation

**Easiest fix:** Just delete the endpoint if you don't need dynamic frontend constraints. The frontend has a fallback list.

