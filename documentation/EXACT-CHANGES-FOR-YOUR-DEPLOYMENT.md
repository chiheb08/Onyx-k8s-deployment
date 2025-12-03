# Exact Changes for Your Deployment Version

## 📍 Your Current Code (What You Have Now)

Based on your screenshot, your `post_index` function currently looks like this (starting at line 252):

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
    
    # don't update the status if the user file is being deleted
    for user_file in user_files:
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

**Notice:** Your version goes **directly** from getting `user_files` to marking them as COMPLETED. There's **no delay** or verification step.

---

## ✅ Step 1: Add the Verification Method First

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

---

## ✅ Step 2: Update the `post_index` Function

**📍 WHERE:** In the `post_index` function, **AFTER** the line that gets `user_files` (around line 208), **BEFORE** the loop that marks files as COMPLETED.

**✏️ YOUR CURRENT CODE (lines 208-237):**

```python
    user_files = (
        self.db_session.query(UserFile).filter(UserFile.id.in_(user_file_ids)).all()
    )
    
    # don't update the status if the user file is being deleted
    for user_file in user_files:
        if user_file.status != UserFileStatus.DELETING:
            user_file.status = UserFileStatus.COMPLETED
        user_file.last_project_sync_at = datetime.datetime.now(
            datetime.timezone.utc
        )
        user_file.chunk_count = result.doc_id_to_new_chunk_cnt[str(user_file.id)]
        user_file.token_count = result.user_file_id_to_token_count[
            str(user_file.id)
        ]
```

**✏️ REPLACE WITH THIS (add the delay + verification BEFORE the loop):**

```python
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
        base_delay = 1.5  # Increased for OpenShift network latency
        per_chunk_delay = 0.05  # 50ms per chunk
        max_delay = 8.0  # Maximum 8 seconds for large files in OpenShift
        
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
```

---

## 📋 Complete NEW Function (What It Should Look Like)

Here's the **complete `post_index` function** after all changes:

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
        base_delay = 1.5  # Increased for OpenShift network latency
        per_chunk_delay = 0.05  # 50ms per chunk
        max_delay = 8.0  # Maximum 8 seconds for large files in OpenShift
        
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

## 🎯 Visual Comparison

### **BEFORE (Your Current Code):**
```
Line 204: user_file_ids = [doc.id for doc in context.updatable_docs]
Line 206-208: user_files = self.db_session.query(...).all()
Line 210: # don't update the status if...
Line 211: for user_file in user_files:  ← DIRECTLY marks as COMPLETED
Line 212:     if user_file.status != UserFileStatus.DELETING:
Line 213:         user_file.status = UserFileStatus.COMPLETED
...
```

### **AFTER (With Changes):**
```
Line 204: user_file_ids = [doc.id for doc in context.updatable_docs]
Line 206-208: user_files = self.db_session.query(...).all()
Line 210: # Smart delay + verification...
Line 211: for user_file in user_files:  ← NEW: Delay + Verification loop
Line 212:     if user_file.status == UserFileStatus.DELETING:
Line 213:         continue
Line 214:     chunk_count = result.doc_id_to_new_chunk_cnt.get(...)
Line 215-234: [NEW CODE: Calculate delay, sleep, verify chunks]
Line 235: # Now mark files as COMPLETED...
Line 236: for user_file in user_files:  ← THEN marks as COMPLETED
Line 237:     if user_file.status != UserFileStatus.DELETING:
Line 238:         user_file.status = UserFileStatus.COMPLETED
...
```

---

## 📝 Step-by-Step Instructions

### **Step 1: Add Verification Method**
1. Open `onyx-repo/backend/onyx/indexing/adapters/user_file_indexing_adapter.py`
2. Find the `lock_context` method (ends around line 95)
3. After the closing `)` of `lock_context`, add a blank line
4. Paste the entire `_verify_chunks_searchable` method (from Step 1 above)
5. Make sure indentation matches (4 spaces, same as other methods)

### **Step 2: Modify `post_index` Function**
1. Find the `post_index` function (starts around line 197)
2. Find the line: `user_files = ( self.db_session.query(UserFile)...` (around line 206-208)
3. **Right after that line** (after line 208), **add a blank line**
4. **Paste the NEW delay + verification loop** (the entire block from `# Smart delay + verification...` to the closing `}` before `# Now mark files as COMPLETED`)
5. **Keep the existing loop** that marks files as COMPLETED (it should still be there after your new code)
6. Make sure the indentation is correct:
   - The new `for user_file in user_files:` loop should be at the same indentation level as the old one
   - Everything inside should be indented 4 more spaces

---

## ✅ What Changed Summary

| What | Before | After |
|------|--------|-------|
| **After getting user_files** | Directly marks as COMPLETED | Adds delay + verification loop first |
| **Delay values** | None | 1.5s base, 0.05s/chunk, 8s max |
| **Verification** | None | Verifies chunks are searchable with 3 retries |
| **Mark as COMPLETED** | Immediately | After delay + verification |

---

## 🎯 Key Points

1. **You're ADDING code**, not replacing the entire function
2. **The new delay + verification loop goes BEFORE the existing loop** that marks files as COMPLETED
3. **The existing loop stays the same** - it still marks files as COMPLETED, just after the delay/verification
4. **You need to add the `_verify_chunks_searchable` method first** (Step 1)

---

**That's it!** After these changes, your function will wait and verify before marking files as COMPLETED, which should fix the intermittent first prompt issue.

