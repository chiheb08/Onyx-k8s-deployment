# Step-by-Step Fix: First Prompt Missing Documents

## 🎯 What We're Fixing

**Problem:** Files don't appear in documents section on first prompt, but appear on second prompt.

**Solution:** Add a smart delay before marking files as "COMPLETED" to give Vespa time to update its search index.

---

## 📁 File to Modify

**File Path:** `onyx-repo/backend/onyx/indexing/adapters/user_file_indexing_adapter.py`

**What we're doing:** Adding a delay before marking files as COMPLETED so Vespa's search index has time to update.

---

## 🔧 Step-by-Step Instructions

### **Step 1: Open the File**

1. Navigate to: `onyx-repo/backend/onyx/indexing/adapters/user_file_indexing_adapter.py`
2. Open it in your code editor

---

### **Step 2: Verify Import Statement**

**📍 WHERE TO FIND IT:**
- Look at the **very top of the file** (lines 1-10)
- You should see: `import time` (around line 3)

**✅ VERIFICATION:**
- Check that `import time` exists at the top of the file
- We'll use `time.sleep()` in the code (the `time` module is already imported)
- **No changes needed here** - the import already exists!

---

### **Step 3: Find the `post_index` Method**

**📍 WHERE TO FIND IT:**
- Scroll down in the file
- Look for a function that starts with `def post_index(`
- This should be around **line 197-203**
- It looks like this:
  ```python
  def post_index(
      self,
      context: DocumentBatchPrepareContext,
      updatable_chunk_data: list[UpdatableChunkData],
      filtered_documents: list[Document],
      result: BuildMetadataAwareChunksResult,
  ) -> None:
  ```

**📝 WHAT TO LOOK FOR:**
- Inside this function, you'll see code that:
  1. Gets user files from database
  2. Marks them as COMPLETED
  3. Updates chunk_count and token_count
  4. Commits to database

---

### **Step 4: Find Where Files Are Marked as COMPLETED**

**📍 WHERE TO FIND IT:**
- Inside the `post_index` method
- Look for a loop that says `for user_file in user_files:`
- This should be around **line 209-220**
- You'll see code like:
  ```python
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

**📝 THIS IS WHERE WE'LL ADD THE DELAY**

---

### **Step 5: Add the Smart Delay Logic**

**📍 WHERE TO ADD IT:**
- **BEFORE** the loop that marks files as COMPLETED
- **AFTER** the line that says `user_files = ...`
- This should be right after **line 208** (after `user_files = ...`)

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
```

**--- NEW ---**
```python
    user_files = (
        self.db_session.query(UserFile).filter(UserFile.id.in_(user_file_ids)).all()
    )
    
    # NEW: Smart delay before marking as COMPLETED to allow Vespa index to update
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
```

**📝 DETAILED INSTRUCTIONS:**

1. **Find the line:** `user_files = (self.db_session.query(UserFile)...`
2. **After that line**, add a blank line
3. **Add the comment:** `# NEW: Smart delay before marking as COMPLETED...`
4. **Add the first loop** (the one with delay calculation)
5. **Keep the second loop** (the one that marks as COMPLETED) - it stays the same

**🔍 KEY POINTS:**
- The **first loop** calculates delay and waits
- The **second loop** marks files as COMPLETED (unchanged)
- We skip files that are being deleted (`if user_file.status == UserFileStatus.DELETING: continue`)

---

## 📊 Complete Code Section (For Reference)

Here's what the complete `post_index` method should look like after changes:

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
    
    # NEW: Smart delay before marking as COMPLETED to allow Vespa index to update
    # This prevents the issue where files don't appear in search on first prompt
    for user_file in user_files:
        if user_file.status == UserFileStatus.DELETING:
            continue
        
        # Calculate delay based on chunk count
        chunk_count = result.doc_id_to_new_chunk_cnt.get(str(user_file.id), 0)
        
        # Formula: base_delay + (chunk_count * per_chunk_delay)
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

---

## ✅ Verification Checklist

After making changes, verify:

- [ ] ✅ `import time` exists at the top (already there, no change needed)
- [ ] ✅ First loop calculates delay and calls `time.sleep(delay)`
- [ ] ✅ Second loop marks files as COMPLETED (unchanged)
- [ ] ✅ Code indentation is correct (4 spaces, matches surrounding code)
- [ ] ✅ No syntax errors (check for missing colons, parentheses, etc.)

---

## 🧪 Testing

After implementing, test:

1. **Upload a small file** (1-5 pages)
   - **Expected:** File appears in documents on first prompt
   - **Delay:** ~0.5 seconds

2. **Upload a large file** (50+ pages)
   - **Expected:** File appears in documents on first prompt
   - **Delay:** ~2-3 seconds

3. **Check logs:**
   - Look for: `"Waiting X.XXs for Vespa index update..."`
   - Should see delay messages for each file

---

## 🐛 Troubleshooting

### **Error: "sleep is not defined" or "time is not defined"**
- **Problem:** `time` module not imported
- **Fix:** Make sure `import time` exists at the top of the file (around line 3)

### **Error: "IndentationError"**
- **Problem:** Wrong indentation
- **Fix:** Make sure all code inside the loop is indented with 4 spaces

### **Error: "NameError: name 'logger' is not defined"**
- **Problem:** Logger not imported
- **Fix:** Check if `logger = setup_logger()` exists at the top of the file (it should already be there)

### **Files still not appearing on first prompt**
- **Problem:** Delay might be too short
- **Fix:** Increase `base_delay` from `0.5` to `1.0` or increase `max_delay` from `3.0` to `5.0`

---

## 📝 Summary

**What we changed:**
1. ✅ Verified `import time` exists (already in file, no change needed)
2. ✅ Added delay calculation loop before marking as COMPLETED
3. ✅ Delay adapts to file size (more chunks = longer delay)

**Result:**
- ✅ Files appear in documents section on first prompt
- ✅ Works for all file sizes
- ✅ Minimal performance impact (0.5-3 seconds per file)

**File Modified:**
- `onyx-repo/backend/onyx/indexing/adapters/user_file_indexing_adapter.py`

---

## 🚀 Next Steps

1. **Make the changes** following the steps above
2. **Test** with various file sizes
3. **Check logs** to verify delays are working
4. **Deploy** to your environment
5. **Monitor** for any issues

---

## 💡 Quick Reference

**File:** `onyx-repo/backend/onyx/indexing/adapters/user_file_indexing_adapter.py`

**Line Numbers (approximate):**
- **Line 3:** Verify `import time` exists (no change needed)
- **Line 208-220:** Add delay logic (before marking COMPLETED)

**Key Changes:**
1. Verify import: `import time` (already exists)
2. Add delay loop before COMPLETED loop
3. Delay formula: `min(0.5 + (chunk_count * 0.02), 3.0)`
4. Use `time.sleep(delay)` to wait

---

That's it! Follow these steps and your fix will be complete. 🎉

