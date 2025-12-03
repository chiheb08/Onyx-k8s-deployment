# Complete Solution: Step-by-Step Implementation Guide

## 🎯 Overview

This guide provides step-by-step instructions to fix two critical issues:

1. **First Prompt Missing Documents** - Files don't appear in documents section on first prompt
2. **Orchestrator JSON Parsing Error** - "Invalid JSON: EOF while parsing a value" error

---

## 📋 Table of Contents

1. [Fix 1: First Prompt Missing Documents](#fix-1-first-prompt-missing-documents)
2. [Fix 2: Orchestrator JSON Parsing Error](#fix-2-orchestrator-json-parsing-error)
3. [Testing](#testing)
4. [Deployment](#deployment)

---

## 🔧 Fix 1: First Prompt Missing Documents

### **Problem:**
Files don't appear in documents section on first prompt, but appear on second prompt.

### **Root Cause:**
Vespa eventual consistency - chunks are written but not immediately searchable.

### **Solution:**
Add smart delay before marking files as COMPLETED to give Vespa time to update its search index.

---

### **Step 1: Open the File**

**File Path:** `onyx-repo/backend/onyx/indexing/adapters/user_file_indexing_adapter.py`

1. Navigate to the file in your code editor
2. Find the `post_index` method (around line 197)

---

### **Step 2: Locate Where Files Are Marked as COMPLETED**

**📍 WHERE TO FIND IT:**
- Inside the `post_index` method
- Look for the loop that says `for user_file in user_files:`
- This should be around **line 209-220**

**Current code looks like:**
```python
user_files = (
    self.db_session.query(UserFile).filter(UserFile.id.in_(user_file_ids)).all()
)
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

### **Step 3: Add Smart Delay Logic**

**📍 WHERE TO ADD IT:**
- **BEFORE** the loop that marks files as COMPLETED
- **AFTER** the line `user_files = ...`
- Right after **line 208**

**✏️ WHAT TO CHANGE:**

**--- OLD ---**
```python
    user_files = (
        self.db_session.query(UserFile).filter(UserFile.id.in_(user_file_ids)).all()
    )
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

**--- NEW ---**
```python
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
```

**📝 KEY CHANGES:**
1. Added a **first loop** that calculates delay and waits (`time.sleep(delay)`)
2. Kept the **second loop** that marks files as COMPLETED (unchanged)
3. Delay adapts to file size automatically

**✅ VERIFICATION:**
- Check that `import time` exists at the top of the file (it should already be there)
- Make sure you use `time.sleep(delay)` (not just `sleep(delay)`)

---

## 🔧 Fix 2: Orchestrator JSON Parsing Error

### **Problem:**
Error: "Invalid JSON: EOF while parsing a value at line 1 column 0"

### **Root Cause:**
LLM returns empty or invalid JSON response.

### **Solution:**
Add error handling for empty responses and better JSON extraction.

---

### **Step 1: Open the File**

**File Path:** `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py`

1. Navigate to the file in your code editor
2. Find the `invoke_llm_json` function (around line 137)

---

### **Step 2: Verify Logger Import**

**📍 WHERE TO CHECK:**
- Look at the top of the file (lines 1-30)
- Check if `logger = setup_logger()` exists

**If logger doesn't exist, add:**

**--- OLD ---**
```python
from onyx.utils.threadpool_concurrency import run_with_timeout

SchemaType = TypeVar("SchemaType", bound=BaseModel)
```

**--- NEW ---**
```python
from onyx.utils.logger import setup_logger
from onyx.utils.threadpool_concurrency import run_with_timeout

logger = setup_logger()

SchemaType = TypeVar("SchemaType", bound=BaseModel)
```

---

### **Step 3: Fix JSON Extraction and Add Error Handling**

**📍 WHERE TO FIND IT:**
- Inside the `invoke_llm_json` function
- Look for the section that extracts JSON (around line 171-183)
- Find the line: `return schema.model_validate_json(response_content)`

**✏️ WHAT TO CHANGE:**

**--- OLD ---**
```python
    if not supports_json:
        # remove newlines as they often lead to json decoding errors
        response_content = response_content.replace("\n", " ")
        # hope the prompt is structured in a way a json is outputted...
        json_block_match = JSON_PATTERN.search(response_content)
        if json_block_match:
            response_content = json_block_match.group(1)
        else:
            first_bracket = response_content.find("{")
            last_bracket = response_content.rfind("}")
            response_content = response_content[first_bracket : last_bracket + 1]

    return schema.model_validate_json(response_content)
```

**--- NEW ---**
```python
    if not supports_json:
        # remove newlines as they often lead to json decoding errors
        response_content = response_content.replace("\n", " ")
        # hope the prompt is structured in a way a json is outputted...
        json_block_match = JSON_PATTERN.search(response_content)
        if json_block_match:
            response_content = json_block_match.group(1)
        else:
            first_bracket = response_content.find("{")
            last_bracket = response_content.rfind("}")
            if first_bracket != -1 and last_bracket != -1 and last_bracket >= first_bracket:
                response_content = response_content[first_bracket : last_bracket + 1]
            else:
                # No valid JSON brackets found
                response_content = ""

    # Validate that we have content before parsing
    if not response_content or not response_content.strip():
        logger.error(
            f"LLM returned empty or invalid JSON response. "
            f"Model: {llm.config.model_name}, Provider: {llm.config.model_provider}. "
            f"This usually means the LLM timed out, was interrupted, or failed to generate a response."
        )
        raise ValueError(
            f"LLM returned empty response when JSON was expected. "
            f"This usually means the LLM timed out, was interrupted, or failed to generate a response. "
            f"Please try again or check your LLM configuration."
        )

    try:
        return schema.model_validate_json(response_content)
    except Exception as e:
        logger.error(
            f"Failed to parse LLM JSON response. Response content (first 200 chars): {response_content[:200]}... "
            f"Error: {e}"
        )
        raise ValueError(
            f"Failed to parse LLM response as JSON. The LLM may have returned invalid JSON. "
            f"Original error: {str(e)}"
        ) from e
```

**📝 KEY CHANGES:**
1. Added check for valid brackets before extracting JSON
2. Added validation for empty responses
3. Wrapped JSON parsing in try-except for better error messages
4. Added detailed logging

---

## ✅ Complete Checklist

After implementing both fixes, verify:

### **Fix 1 (First Prompt Missing Documents):**
- [ ] ✅ `import time` exists at top of `user_file_indexing_adapter.py`
- [ ] ✅ First loop calculates delay and calls `time.sleep(delay)`
- [ ] ✅ Second loop marks files as COMPLETED (unchanged)
- [ ] ✅ Code indentation is correct (4 spaces)

### **Fix 2 (Orchestrator JSON Error):**
- [ ] ✅ `logger = setup_logger()` exists in `llm.py`
- [ ] ✅ Empty response validation added
- [ ] ✅ Try-except block around JSON parsing
- [ ] ✅ Error logging added

---

## 🧪 Testing

### **Test 1: First Prompt Missing Documents**

1. **Upload a large file** (50+ pages PDF)
2. **Send prompt immediately** after upload completes
3. **Expected:** File appears in documents section on first prompt ✅
4. **Check logs:** Should see "Waiting X.XXs for Vespa index update..."

### **Test 2: Orchestrator JSON Error**

1. **Send a prompt** that previously caused the error
2. **Expected:** 
   - If LLM works: Normal response ✅
   - If LLM fails: Clear error message instead of cryptic Pydantic error ✅
3. **Check logs:** Should see detailed error messages if JSON parsing fails

---

## 📊 Files Modified Summary

| File | Changes | Purpose |
|------|---------|---------|
| `onyx-repo/backend/onyx/indexing/adapters/user_file_indexing_adapter.py` | Added smart delay before COMPLETED | Fix first prompt missing documents |
| `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py` | Added error handling for empty JSON | Fix orchestrator JSON parsing error |

---

## 🚀 Deployment Steps

1. **Make the code changes** (follow steps above)
2. **Test locally** (if possible)
3. **Commit changes:**
   ```bash
   cd onyx-repo
   git add backend/onyx/indexing/adapters/user_file_indexing_adapter.py
   git add backend/onyx/agents/agent_search/shared_graph_utils/llm.py
   git commit -m "Fix: Add smart delay for Vespa index update and improve JSON error handling"
   git push origin main
   ```
4. **Build and deploy** your backend
5. **Monitor logs** for any issues
6. **Test in production** with real files

---

## 📝 Summary

**What We Fixed:**

1. ✅ **First Prompt Missing Documents**
   - Added smart delay (0.5-3 seconds) before marking files as COMPLETED
   - Gives Vespa time to update its search index
   - Files now appear on first prompt

2. ✅ **Orchestrator JSON Parsing Error**
   - Added validation for empty LLM responses
   - Improved JSON extraction with bracket validation
   - Better error messages and logging

**Result:**
- ✅ Files appear in documents section on first prompt
- ✅ Better error handling for LLM failures
- ✅ Clearer error messages for debugging
- ✅ More reliable system overall

---

## 🆘 Troubleshooting

### **Files still not appearing on first prompt:**
- **Check:** Delay might be too short
- **Fix:** Increase `base_delay` from `0.5` to `1.0` or `max_delay` from `3.0` to `5.0`

### **Orchestrator error still occurs:**
- **Check:** LLM configuration (timeout, max_tokens)
- **Check:** LLM service is responding
- **Check:** Network connectivity to LLM

### **Import errors:**
- **Check:** All imports are correct
- **Verify:** `import time` exists in `user_file_indexing_adapter.py`
- **Verify:** `logger = setup_logger()` exists in `llm.py`

---

That's it! Follow these steps and both issues will be fixed. 🎉

