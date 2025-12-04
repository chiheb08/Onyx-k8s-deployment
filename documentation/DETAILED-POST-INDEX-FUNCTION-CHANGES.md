# Detailed Explanation: `post_index` Function Changes

## 📍 Overview

This document shows the **complete `post_index` function** - both the **OLD version** (current code) and the **NEW version** (with all improvements). This makes it easy to see exactly what needs to change.

---

## 📁 File Location

**File:** `onyx-repo/backend/onyx/indexing/adapters/user_file_indexing_adapter.py`

**Function:** `post_index` (starts at line 197)

---

## 🔧 Step 1: Add the Verification Method First

**📍 WHERE:** Add this method **inside the `UserFileIndexingAdapter` class**, **after the `lock_context` method** (around line 95), **before the `build_metadata_aware_chunks` method**.

**✏️ ADD THIS CODE:**

```python
def _verify_chunks_searchable(
    self, user_file_id: str, expected_chunk_count: int, tenant_id: str
) -> bool:
    """
    Verify that chunks are actually searchable in Vespa before marking as COMPLETED.
    
    Returns True if at least one chunk is found, False otherwise.
    """
    from onyx.document_index.vespa.chunk_retrieval import query_vespa
    from onyx.document_index.vespa_constants import YQL_BASE
    from onyx.document_index.vespa.shared_utils.vespa_request_builders import build_vespa_filters
    from onyx.context.search.models import IndexFilters
    from onyx.configs.app_configs import MULTI_TENANT
    from uuid import UUID
    
    try:
        # Build a simple query to check if chunks exist
        filters = IndexFilters(
            user_file_ids=[UUID(user_file_id)],
            access_control_list=[],
            tenant_id=tenant_id if MULTI_TENANT else None,
        )
        
        filters_str = build_vespa_filters(filters=filters, include_hidden=False)
        
        # Get the index name from settings
        from onyx.db.search_settings import get_active_search_settings
        active_settings = get_active_search_settings(self.db_session)
        index_name = active_settings.primary.index_name
        
        yql = YQL_BASE.format(index_name=index_name) + filters_str + "limit 5"
        
        # Remove trailing " and " if present
        if yql.endswith(" and "):
            yql = yql[:-5]
        
        params = {
            "yql": yql,
            "hits": 5,
        }
        
        chunks = query_vespa(params)
        found_count = len(chunks)
        
        logger.debug(
            f"Verification query found {found_count} chunks for user_file {user_file_id} "
            f"(expected at least 1 of {expected_chunk_count})"
        )
        
        return found_count > 0
        
    except Exception as e:
        logger.warning(f"Failed to verify chunks searchable for {user_file_id}: {e}")
        return False  # Assume not ready if verification fails
```

**📝 WHERE EXACTLY:**
- Open the file `user_file_indexing_adapter.py`
- Find the `lock_context` method (ends around line 95)
- Right after the closing `)` of `lock_context`, add a blank line
- Then paste the entire `_verify_chunks_searchable` method above
- Make sure the indentation matches (should be at the same level as `lock_context` - 4 spaces)

---

## 📋 Complete OLD `post_index` Function (Current Code)

Here's the **entire function as it currently exists** (lines 197-258):

```python
def post_index(
    self,
    context: DocumentBatchPrepareContext,
    updatable_chunk_data: list[UpdatableChunkData],
    filtered_documents: list[Document],
    result: BuildMetadataAwareChunksResult,
) -> None:
    user_file_ids = [doc.id for doc in context.updatable_docs]

    user_files = (
        self.db_session.query(UserFile).filter(UserFile.id.in_(user_file_ids)).all()
    )
    
    # Smart delay before marking as COMPLETED to allow Vespa index to update
    # This prevents the issue where files don't appear in search on first prompt
    for user_file in user_files:
        if user_file.status == UserFileStatus.DELETING:
            continue
        
        # Calculate delay based on chunk count
        # More chunks = longer index update time needed
        chunk_count = result.doc_id_to_new_chunk_cnt.get(str(user_file.id), 0)
        
        # Formula: base_delay + (chunk_count * per_chunk_delay)
        # - Small files (< 10 chunks): 0.5s
        # - Medium files (10-50 chunks): 0.5-1.5s
        # - Large files (> 50 chunks): 1.5-3s
        base_delay = 0.5
        per_chunk_delay = 0.02  # 20ms per chunk
        max_delay = 3.0  # Maximum 3 seconds
        
        delay = min(base_delay + (chunk_count * per_chunk_delay), max_delay)
        
        logger.debug(
            f"Waiting {delay:.2f}s for Vespa index update before marking file {user_file.id} "
            f"as COMPLETED (chunk_count={chunk_count})"
        )
        time.sleep(delay)
    
    # Now mark files as COMPLETED (Vespa index should be updated by now)
    for user_file in user_files:
        # don't update the status if the user file is being deleted
        if user_file.status != UserFileStatus.DELETING:
            user_file.status = UserFileStatus.COMPLETED
        user_file.last_project_sync_at = datetime.datetime.now(
            datetime.timezone.utc
        )
        user_file.chunk_count = result.doc_id_to_new_chunk_cnt[str(user_file.id)]
        user_file.token_count = result.user_file_id_to_token_count[
            str(user_file.id)
        ]
    self.db_session.commit()

    # Store the plaintext in the file store for faster retrieval
    # NOTE: this creates its own session to avoid committing the overall
    # transaction.
    for user_file_id, raw_text in result.user_file_id_to_raw_text.items():
        store_user_file_plaintext(
            user_file_id=UUID(user_file_id),
            plaintext_content=raw_text,
        )
```

---

## ✅ Complete NEW `post_index` Function (With All Changes)

Here's the **entire function with all improvements** - replace the entire function above with this:

```python
def post_index(
    self,
    context: DocumentBatchPrepareContext,
    updatable_chunk_data: list[UpdatableChunkData],
    filtered_documents: list[Document],
    result: BuildMetadataAwareChunksResult,
) -> None:
    user_file_ids = [doc.id for doc in context.updatable_docs]

    user_files = (
        self.db_session.query(UserFile).filter(UserFile.id.in_(user_file_ids)).all()
    )
    
    # Smart delay + verification before marking as COMPLETED
    # This prevents the issue where files don't appear in search on first prompt
    for user_file in user_files:
        if user_file.status == UserFileStatus.DELETING:
            continue
        
        chunk_count = result.doc_id_to_new_chunk_cnt.get(str(user_file.id), 0)
        
        # Initial delay based on chunk count (increased for OpenShift environments)
        # Formula: base_delay + (chunk_count * per_chunk_delay)
        # - Small files (< 10 chunks): 1.5-2s
        # - Medium files (10-50 chunks): 2-4s
        # - Large files (> 50 chunks): 4-8s
        base_delay = 1.5  # Increased from 0.5s for OpenShift network latency
        per_chunk_delay = 0.05  # Increased from 0.02s (50ms per chunk)
        max_delay = 8.0  # Increased from 3.0s to handle large files in OpenShift
        
        initial_delay = min(base_delay + (chunk_count * per_chunk_delay), max_delay)
        
        logger.debug(
            f"Waiting {initial_delay:.2f}s for Vespa index update before verification "
            f"for file {user_file.id} (chunk_count={chunk_count})"
        )
        time.sleep(initial_delay)
        
        # Verify chunks are actually searchable (with retries)
        max_verification_attempts = 3
        chunks_searchable = False
        
        for attempt in range(max_verification_attempts):
            chunks_searchable = self._verify_chunks_searchable(
                user_file_id=str(user_file.id),
                expected_chunk_count=chunk_count,
                tenant_id=self.tenant_id,
            )
            
            if chunks_searchable:
                logger.info(
                    f"Chunks verified searchable for file {user_file.id} on attempt {attempt + 1}"
                )
                break
            else:
                if attempt < max_verification_attempts - 1:
                    retry_delay = 2.0 * (attempt + 1)  # 2s, 4s
                    logger.warning(
                        f"Chunks not yet searchable for file {user_file.id}, "
                        f"retrying verification in {retry_delay}s "
                        f"(attempt {attempt + 1}/{max_verification_attempts})"
                    )
                    time.sleep(retry_delay)
        
        if not chunks_searchable:
            logger.error(
                f"Chunks still not searchable after {max_verification_attempts} attempts "
                f"for file {user_file.id}. Marking as COMPLETED anyway to avoid blocking."
            )
    
    # Now mark files as COMPLETED (Vespa index should be updated by now)
    for user_file in user_files:
        # don't update the status if the user file is being deleted
        if user_file.status != UserFileStatus.DELETING:
            user_file.status = UserFileStatus.COMPLETED
        user_file.last_project_sync_at = datetime.datetime.now(
            datetime.timezone.utc
        )
        user_file.chunk_count = result.doc_id_to_new_chunk_cnt[str(user_file.id)]
        user_file.token_count = result.user_file_id_to_token_count[
            str(user_file.id)
        ]
    self.db_session.commit()

    # Store the plaintext in the file store for faster retrieval
    # NOTE: this creates its own session to avoid committing the overall
    # transaction.
    for user_file_id, raw_text in result.user_file_id_to_raw_text.items():
        store_user_file_plaintext(
            user_file_id=UUID(user_file_id),
            plaintext_content=raw_text,
        )
```

---

## 🔍 What Changed? (Line-by-Line Comparison)

### **Section 1: Function Signature & Initial Setup**
**Lines 197-208:** ✅ **NO CHANGES** - Keep as is

```python
def post_index(
    self,
    context: DocumentBatchPrepareContext,
    updatable_chunk_data: list[UpdatableChunkData],
    filtered_documents: list[Document],
    result: BuildMetadataAwareChunksResult,
) -> None:
    user_file_ids = [doc.id for doc in context.updatable_docs]

    user_files = (
        self.db_session.query(UserFile).filter(UserFile.id.in_(user_file_ids)).all()
    )
```

---

### **Section 2: The Delay Loop (THIS IS WHERE CHANGES HAPPEN)**

**📍 OLD CODE (Lines 210-234):**
```python
    # Smart delay before marking as COMPLETED to allow Vespa index to update
    # This prevents the issue where files don't appear in search on first prompt
    for user_file in user_files:
        if user_file.status == UserFileStatus.DELETING:
            continue
        
        # Calculate delay based on chunk count
        # More chunks = longer index update time needed
        chunk_count = result.doc_id_to_new_chunk_cnt.get(str(user_file.id), 0)
        
        # Formula: base_delay + (chunk_count * per_chunk_delay)
        # - Small files (< 10 chunks): 0.5s
        # - Medium files (10-50 chunks): 0.5-1.5s
        # - Large files (> 50 chunks): 1.5-3s
        base_delay = 0.5
        per_chunk_delay = 0.02  # 20ms per chunk
        max_delay = 3.0  # Maximum 3 seconds
        
        delay = min(base_delay + (chunk_count * per_chunk_delay), max_delay)
        
        logger.debug(
            f"Waiting {delay:.2f}s for Vespa index update before marking file {user_file.id} "
            f"as COMPLETED (chunk_count={chunk_count})"
        )
        time.sleep(delay)
```

**📍 NEW CODE (Replace the entire section above with this):**
```python
    # Smart delay + verification before marking as COMPLETED
    # This prevents the issue where files don't appear in search on first prompt
    for user_file in user_files:
        if user_file.status == UserFileStatus.DELETING:
            continue
        
        chunk_count = result.doc_id_to_new_chunk_cnt.get(str(user_file.id), 0)
        
        # Initial delay based on chunk count (increased for OpenShift environments)
        # Formula: base_delay + (chunk_count * per_chunk_delay)
        # - Small files (< 10 chunks): 1.5-2s
        # - Medium files (10-50 chunks): 2-4s
        # - Large files (> 50 chunks): 4-8s
        base_delay = 1.5  # Increased from 0.5s for OpenShift network latency
        per_chunk_delay = 0.05  # Increased from 0.02s (50ms per chunk)
        max_delay = 8.0  # Increased from 3.0s to handle large files in OpenShift
        
        initial_delay = min(base_delay + (chunk_count * per_chunk_delay), max_delay)
        
        logger.debug(
            f"Waiting {initial_delay:.2f}s for Vespa index update before verification "
            f"for file {user_file.id} (chunk_count={chunk_count})"
        )
        time.sleep(initial_delay)
        
        # Verify chunks are actually searchable (with retries)
        max_verification_attempts = 3
        chunks_searchable = False
        
        for attempt in range(max_verification_attempts):
            chunks_searchable = self._verify_chunks_searchable(
                user_file_id=str(user_file.id),
                expected_chunk_count=chunk_count,
                tenant_id=self.tenant_id,
            )
            
            if chunks_searchable:
                logger.info(
                    f"Chunks verified searchable for file {user_file.id} on attempt {attempt + 1}"
                )
                break
            else:
                if attempt < max_verification_attempts - 1:
                    retry_delay = 2.0 * (attempt + 1)  # 2s, 4s
                    logger.warning(
                        f"Chunks not yet searchable for file {user_file.id}, "
                        f"retrying verification in {retry_delay}s "
                        f"(attempt {attempt + 1}/{max_verification_attempts})"
                    )
                    time.sleep(retry_delay)
        
        if not chunks_searchable:
            logger.error(
                f"Chunks still not searchable after {max_verification_attempts} attempts "
                f"for file {user_file.id}. Marking as COMPLETED anyway to avoid blocking."
            )
```

**📝 KEY CHANGES:**
1. **Line 224:** `base_delay = 0.5` → `base_delay = 1.5` (increased)
2. **Line 225:** `per_chunk_delay = 0.02` → `per_chunk_delay = 0.05` (increased)
3. **Line 226:** `max_delay = 3.0` → `max_delay = 8.0` (increased)
4. **Line 228:** `delay = ...` → `initial_delay = ...` (renamed variable)
5. **Line 230-234:** Changed log message and variable name
6. **Lines 236-260:** **NEW CODE** - Added verification loop with retries (this is completely new)

---

### **Section 3: Mark Files as COMPLETED**
**Lines 236-248:** ✅ **NO CHANGES** - Keep as is

```python
    # Now mark files as COMPLETED (Vespa index should be updated by now)
    for user_file in user_files:
        # don't update the status if the user file is being deleted
        if user_file.status != UserFileStatus.DELETING:
            user_file.status = UserFileStatus.COMPLETED
        user_file.last_project_sync_at = datetime.datetime.now(
            datetime.timezone.utc
        )
        user_file.chunk_count = result.doc_id_to_new_chunk_cnt[str(user_file.id)]
        user_file.token_count = result.user_file_id_to_token_count[
            str(user_file.id)
        ]
    self.db_session.commit()
```

---

### **Section 4: Store Plaintext**
**Lines 250-258:** ✅ **NO CHANGES** - Keep as is

```python
    # Store the plaintext in the file store for faster retrieval
    # NOTE: this creates its own session to avoid committing the overall
    # transaction.
    for user_file_id, raw_text in result.user_file_id_to_raw_text.items():
        store_user_file_plaintext(
            user_file_id=UUID(user_file_id),
            plaintext_content=raw_text,
        )
```

---

## 📝 Step-by-Step Instructions

### **Step 1: Add the Verification Method**
1. Open `onyx-repo/backend/onyx/indexing/adapters/user_file_indexing_adapter.py`
2. Find the `lock_context` method (ends around line 95)
3. After the closing `)` of `lock_context`, add a blank line
4. Paste the entire `_verify_chunks_searchable` method (from Step 1 above)
5. Make sure indentation matches (4 spaces, same as other methods)

### **Step 2: Replace the Delay Section**
1. Find the `post_index` function (starts at line 197)
2. Find the comment `# Smart delay before marking as COMPLETED...` (around line 210)
3. **Select everything from line 210 to line 234** (the entire delay loop)
4. **Delete it**
5. **Replace with the NEW CODE** from Section 2 above (the new delay + verification loop)
6. Make sure the indentation is correct (should be inside the `for user_file in user_files:` loop)

### **Step 3: Verify the Rest is Unchanged**
1. Check that lines 236-258 (marking as COMPLETED and storing plaintext) are **unchanged**
2. The function should end with `store_user_file_plaintext(...)`

---

## ✅ Visual Guide: What the Function Looks Like

```
post_index function:
├── Function signature (lines 197-203) ✅ NO CHANGE
├── Get user_files (lines 204-208) ✅ NO CHANGE
├── DELAY + VERIFICATION LOOP (lines 210-260) ⚠️ THIS CHANGES
│   ├── Check if DELETING ✅ NO CHANGE
│   ├── Calculate initial_delay ⚠️ CHANGED (values increased)
│   ├── Sleep initial_delay ⚠️ CHANGED (variable renamed)
│   ├── Verification loop ⚠️ NEW CODE (entire section)
│   └── Error logging ⚠️ NEW CODE
├── Mark as COMPLETED (lines 236-248) ✅ NO CHANGE
└── Store plaintext (lines 250-258) ✅ NO CHANGE
```

---

## 🎯 Summary

**What you need to do:**
1. ✅ Add `_verify_chunks_searchable` method (new method, ~60 lines)
2. ✅ Replace lines 210-234 with the new delay + verification code (~50 lines)
3. ✅ Keep everything else the same

**Total changes:**
- **1 new method** added to the class
- **~25 lines replaced** in `post_index` function
- **Rest of function unchanged**

---

**That's it!** The function is now more robust and will verify chunks are searchable before marking files as COMPLETED.


