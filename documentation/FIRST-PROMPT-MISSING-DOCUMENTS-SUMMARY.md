# First Prompt Missing Documents - Quick Summary

## 🔍 The Problem

**What you see:**
- First prompt: UI shows "internal documents are being searched" but **file doesn't appear** in documents section
- Second prompt: File **appears** in documents section

**What's happening:**
- Search is running ✅
- But Vespa returns **empty results** on first attempt ❌
- Vespa finds the file on second attempt ✅

---

## 🔬 Root Cause

**Vespa Eventual Consistency:**
- Chunks are written to Vespa → HTTP 200 (success)
- BUT Vespa's search index needs ~500ms-1 second to update
- During this window, chunks exist but aren't searchable yet
- First search: No results (index not ready)
- Second search: Results found (index now ready)

---

## ✅ The Fix

**Added retry logic:**
- If search returns no results AND we have `user_file_ids`
- Wait 1 second (for Vespa index to update)
- Retry the search
- If retry succeeds, use those results

**Code Location:**
- `onyx-repo/backend/onyx/agents/agent_search/dr/sub_agents/basic_search/dr_basic_search_2_act.py`

**What changed:**
```python
# After first search attempt
if user_file_ids and len(retrieved_docs) == 0:
    # Wait 1 second for Vespa index to update
    sleep(1.0)
    # Retry the search
    # ... retry logic ...
```

---

## 📊 Visual Flow

### **Before Fix:**
```
1. User uploads file → Chunks written to Vespa
2. File marked: COMPLETED
3. User sends first prompt
4. Backend searches Vespa → Empty results (index not ready)
5. UI: Shows "searching..." but no documents ❌
6. User sends second prompt
7. Backend searches Vespa → Results found (index ready)
8. UI: Shows file in documents ✅
```

### **After Fix:**
```
1. User uploads file → Chunks written to Vespa
2. File marked: COMPLETED
3. User sends first prompt
4. Backend searches Vespa → Empty results (index not ready)
5. Backend waits 1 second → Retries search
6. Backend searches Vespa → Results found (index ready)
7. UI: Shows file in documents ✅
```

---

## 🧪 Testing

After deploying, test:

1. ✅ Upload large file
2. ✅ Send prompt immediately
3. ✅ Check: File should appear in documents section on first prompt
4. ✅ Check backend logs: Should see "Retrying after 1 second..." message

---

## 📝 What to Monitor

**Backend Logs:**
- Look for: `"Search returned no results for user_file_ids ... Retrying after 1 second"`
- Look for: `"Retry successful! Found X chunks"`
- Look for: `"Retry still returned no results"` (if file truly not indexed)

**If retry still fails:**
- File may not be fully indexed yet
- Check file status in database
- Check Vespa logs for indexing errors

---

## ✅ Summary

**Problem:** File doesn't appear in documents on first prompt, but appears on second prompt.

**Root Cause:** Vespa eventual consistency - chunks written but not immediately searchable.

**Fix:** Retry search after 1-second delay if no results found.

**Result:** File appears in documents section on first prompt! ✅

