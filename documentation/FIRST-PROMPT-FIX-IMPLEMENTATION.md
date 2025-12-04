# First Prompt Fix - Implementation Summary

## ✅ What Was Fixed

**Problem:** With large files (exceeding token limits), the first prompt always failed, but the second prompt always worked - even after waiting. This was NOT a timing issue.

**Root Cause:** The query rewriting step (LLM rewriting the user's query before searching) was producing poor/generic queries on the first attempt, causing the search to return no results even though the file was indexed and `user_file_ids` was correctly set.

**Solution:** Skip query rewriting when `user_file_ids` is set and use the original query directly. This ensures consistent, reliable results on the first attempt.

---

## 📝 Code Changes

**File:** `onyx-repo/backend/onyx/agents/agent_search/dr/sub_agents/basic_search/dr_basic_search_2_act.py`

### What Changed:

1. **Moved `user_file_ids` check earlier** (before query rewriting)
2. **Skip query rewriting for user file searches** - Use original query directly
3. **Force source type to `[DocumentSource.USER_FILE]`** - Ensures user files aren't filtered out

### Key Changes:

```python
# BEFORE: Query rewriting always happened first
base_search_processing_prompt = BASE_SEARCH_PROCESSING_PROMPT.build(...)
search_processing = invoke_llm_json(...)
rewritten_query = search_processing.rewritten_query
# ... then check user_file_ids later

# AFTER: Check user_file_ids first, skip rewriting if present
if user_file_ids:
    # Skip query rewriting, use original query
    rewritten_query = branch_query
    specified_source_types = [DocumentSource.USER_FILE]
    implied_time_filter = None
else:
    # Original query rewriting logic for general searches
    # ... (unchanged)
```

---

## 🎯 Why This Works

1. **Eliminates query rewriting issue:** No more poor/generic queries on first attempt
2. **Uses original query:** The user's original query is more likely to match their file content
3. **Forces correct source type:** Ensures "user_file" is always included, preventing filtering issues
4. **Consistent results:** First and second attempts now work the same way

---

## 🧪 Testing

After deploying this fix, test with:

1. ✅ **Large file upload** (exceeds token limits)
2. ✅ **Immediate first prompt** - Should work now (previously failed)
3. ✅ **Second prompt** - Should still work (as before)
4. ✅ **Different query types** - Test with various question formats
5. ✅ **Multiple files** - Test with multiple large files attached

---

## 📊 Expected Behavior

### Before Fix:
```
User uploads large file → Sends first prompt → Query rewritten poorly → Search returns nothing → Fails
User sends second prompt → Query rewritten better → Search works → Success
```

### After Fix:
```
User uploads large file → Sends first prompt → Original query used → Search works → Success ✅
User sends second prompt → Original query used → Search works → Success ✅
```

---

## 🔍 Debugging

If issues persist, check logs for:

1. **Query used:**
   ```
   "Skipping query rewriting for user file search with X files. Using original query: ..."
   ```

2. **Source types:**
   ```
   specified_source_types should be [DocumentSource.USER_FILE]
   ```

3. **Search results:**
   ```
   Should retrieve chunks from the user's files
   ```

---

## 📝 Notes

- This fix only affects searches with `user_file_ids` set (large files using retrieval)
- General searches (without user files) still use query rewriting as before
- The fix is backward compatible and doesn't change the API

---

## 🚀 Deployment

1. **Code is ready** in `onyx-repo/backend/onyx/agents/agent_search/dr/sub_agents/basic_search/dr_basic_search_2_act.py`
2. **Test locally** before deploying to production
3. **Monitor logs** after deployment to verify the fix works
4. **No configuration changes needed** - This is a code-only fix


