# Practical Solution: First Prompt Missing Documents

## 🎯 The Problem

- **First prompt:** UI shows "searching..." but file doesn't appear in documents
- **Second prompt:** File appears in documents
- **Root cause:** Vespa eventual consistency (chunks written but not immediately searchable)

---

## ✅ Complete Solution (3 Layers)

### **Layer 1: Smart Delay Before Marking COMPLETED** ⭐ **RECOMMENDED**

**Why:** Prevents the issue at the source by giving Vespa time to update its index.

**Implementation:**

**File:** `onyx-repo/backend/onyx/indexing/adapters/user_file_indexing_adapter.py`

**Location:** In `post_index` method, before marking files as COMPLETED

**Code Change:**

```python
# Add import at top
from time import sleep

# ... existing code ...

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
    
    # NEW: Smart delay based on chunk count before marking as COMPLETED
    # This gives Vespa time to update its search index
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
        sleep(delay)
    
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
    for user_file_id, raw_text in result.user_file_id_to_raw_text.items():
        store_user_file_plaintext(
            user_file_id=UUID(user_file_id),
            plaintext_content=raw_text,
        )
```

**Benefits:**
- ✅ Simple to implement (just add delay)
- ✅ Prevents issue at source
- ✅ Adapts to file size automatically
- ✅ No complex verification logic needed

**Performance Impact:**
- Small files: +0.5s processing time
- Medium files: +1-1.5s processing time
- Large files: +2-3s processing time

---

### **Layer 2: Improved Retry Logic** ✅ **ALREADY IMPLEMENTED**

**Why:** Safety net if Layer 1 misses something.

**Status:** ✅ Already implemented in `dr_basic_search_2_act.py`

**Current Implementation:**
- Waits 1 second and retries if no results
- Logs warnings and success messages

**Improvement (Optional):**

**File:** `onyx-repo/backend/onyx/agents/agent_search/dr/sub_agents/basic_search/dr_basic_search_2_act.py`

**Replace current retry logic with exponential backoff:**

```python
# If we have user_file_ids but got no results, retry with exponential backoff
if user_file_ids and len(retrieved_docs) == 0:
    logger.warning(
        f"Search returned no results for user_file_ids {user_file_ids} on first attempt. "
        f"Retrying with exponential backoff..."
    )
    
    # Exponential backoff: 0.5s, 1s, 2s
    retry_delays = [0.5, 1.0, 2.0]
    
    for retry_num, delay in enumerate(retry_delays, start=1):
        sleep(delay)
        
        # Retry the search
        callback_container.clear()
        for tool_response in search_tool.run(
            query=rewritten_query,
            document_sources=specified_source_types,
            time_filter=implied_time_filter,
            override_kwargs=SearchToolOverrideKwargs(
                force_no_rerank=True,
                alternate_db_session=search_db_session,
                retrieved_sections_callback=callback_container.append,
                skip_query_analysis=True,
                original_query=rewritten_query,
                user_file_ids=user_file_ids,
                project_id=project_id,
            ),
        ):
            if tool_response.id == SEARCH_RESPONSE_SUMMARY_ID:
                response = cast(SearchResponseSummary, tool_response.response)
                retrieved_docs = response.top_sections
                break
        
        if len(retrieved_docs) > 0:
            logger.info(
                f"Retry {retry_num} successful! Found {len(retrieved_docs)} chunks"
            )
            break
        else:
            logger.debug(f"Retry {retry_num} still returned no results (waited {delay}s)")
    
    if len(retrieved_docs) == 0:
        logger.warning(
            f"All retries failed for user_file_ids {user_file_ids}. "
            f"File may not be fully indexed yet."
        )
```

**Benefits:**
- ✅ Multiple retry attempts (better chance of success)
- ✅ Exponential backoff (smarter timing)
- ✅ Better logging

---

### **Layer 3: Environment Variable Control** (Optional)

**Why:** Allows tuning delay without code changes.

**Implementation:**

**File:** `onyx-repo/backend/onyx/configs/app_configs.py`

**Add:**

```python
# Vespa index update delay configuration
# Delay before marking user files as COMPLETED to allow Vespa index to update
# Format: base_delay,per_chunk_delay,max_delay (all in seconds)
# Example: "0.5,0.02,3.0" = 0.5s base + 0.02s per chunk, max 3s
VESPA_INDEX_UPDATE_DELAY_CONFIG = os.environ.get(
    "VESPA_INDEX_UPDATE_DELAY_CONFIG", "0.5,0.02,3.0"
)

def _parse_vespa_delay_config() -> tuple[float, float, float]:
    """Parse VESPA_INDEX_UPDATE_DELAY_CONFIG environment variable."""
    parts = VESPA_INDEX_UPDATE_DELAY_CONFIG.split(",")
    if len(parts) != 3:
        return (0.5, 0.02, 3.0)  # Default values
    try:
        return (float(parts[0]), float(parts[1]), float(parts[2]))
    except ValueError:
        return (0.5, 0.02, 3.0)  # Default on error

VESPA_DELAY_BASE, VESPA_DELAY_PER_CHUNK, VESPA_DELAY_MAX = _parse_vespa_delay_config()
```

**In `user_file_indexing_adapter.py`:**

```python
from onyx.configs.app_configs import (
    VESPA_DELAY_BASE,
    VESPA_DELAY_PER_CHUNK,
    VESPA_DELAY_MAX,
)

# ... in post_index method ...

delay = min(
    VESPA_DELAY_BASE + (chunk_count * VESPA_DELAY_PER_CHUNK),
    VESPA_DELAY_MAX
)
```

**ConfigMap (`05-configmap.yaml`):**

```yaml
data:
  # ... existing config ...
  
  # Vespa index update delay (base_delay,per_chunk_delay,max_delay in seconds)
  # Adjust if files still not appearing on first prompt
  VESPA_INDEX_UPDATE_DELAY_CONFIG: "0.5,0.02,3.0"
```

**Benefits:**
- ✅ Tunable without code changes
- ✅ Can adjust per environment
- ✅ Easy to experiment with different values

---

## 📊 Complete Solution Summary

### **Recommended Implementation:**

1. ✅ **Layer 2 (Retry Logic)** - Already done
2. ⏭️ **Layer 1 (Smart Delay)** - Implement next (prevents issue)
3. ⏭️ **Layer 3 (Env Var Control)** - Optional (for tuning)

### **Expected Results:**

- ✅ File appears in documents section on first prompt
- ✅ Works for all file sizes
- ✅ Handles edge cases
- ✅ Minimal performance impact

---

## 🧪 Testing

### **Test 1: Small File**
1. Upload 1-page PDF
2. Send prompt immediately
3. **Expected:** File appears ✅
4. **Check logs:** Should see delay ~0.5s

### **Test 2: Large File**
1. Upload 100-page PDF
2. Send prompt immediately
3. **Expected:** File appears ✅
4. **Check logs:** Should see delay ~2-3s

### **Test 3: Multiple Files**
1. Upload 3 files simultaneously
2. Send prompt immediately
3. **Expected:** All files appear ✅

---

## 📝 Step-by-Step Implementation

### **Step 1: Implement Layer 1 (Smart Delay)**

1. Open `onyx-repo/backend/onyx/indexing/adapters/user_file_indexing_adapter.py`
2. Add `from time import sleep` to imports
3. In `post_index` method, before the loop that marks files as COMPLETED:
   - Add the smart delay calculation
   - Add `sleep(delay)` for each file
4. Test with a large file upload

### **Step 2: (Optional) Improve Layer 2 (Retry Logic)**

1. Open `onyx-repo/backend/onyx/agents/agent_search/dr/sub_agents/basic_search/dr_basic_search_2_act.py`
2. Replace current retry logic with exponential backoff version
3. Test with edge cases

### **Step 3: (Optional) Add Layer 3 (Env Var Control)**

1. Add config to `app_configs.py`
2. Update `user_file_indexing_adapter.py` to use config
3. Add to `05-configmap.yaml`
4. Test with different values

---

## ✅ Summary

**Complete Solution = Layer 1 + Layer 2**

- **Layer 1:** Smart delay before marking COMPLETED (prevents issue)
- **Layer 2:** Retry logic in search (safety net)

**Result:**
- ✅ File appears on first prompt
- ✅ Works for all file sizes
- ✅ Simple to implement
- ✅ Minimal performance impact

**Next Steps:**
1. Implement Layer 1 (smart delay)
2. Test with various file sizes
3. Monitor logs for any issues
4. Adjust delay values if needed

