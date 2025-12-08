# Solution: Deleted Files Appear in Thinking Window During Search

## 🐛 Problem Statement

**Issue Reported by Colleague:**
- Upload file A
- Delete file A
- Upload file B
- Ask a question
- **The thinking window displays the deleted file A** ✗

**Root Cause:**
Even though search results are filtered to exclude deleted files, the **thinking window** (which shows documents being searched) displays deleted files because the validation happens too late in the pipeline.

---

## 🔍 Root Cause Analysis

### The Problem Flow

```
1. User uploads file A
   ↓
2. File A indexed in Vespa
   ↓
3. User deletes file A
   ↓
4. Vespa deletion may be delayed/failed
   ↓
5. User uploads file B
   ↓
6. User asks question
   ↓
7. Search runs → Finds chunks from file A (still in Vespa)
   ↓
8. Chunks converted to InferenceSections
   ↓
9. InferenceSections converted to SavedSearchDoc
   ↓
10. SavedSearchDoc sent to frontend in SearchToolDelta packets
   ↓
11. Frontend displays in thinking window ✗ BUG!
```

### Why Current Fix Isn't Enough

**Current Fix Location**: `backend/onyx/context/search/retrieval/search_runner.py`

**Problem**: The validation in `_filter_deleted_user_files()` filters chunks, but:
1. **Race Condition**: Chunks might pass validation if deletion is in progress
2. **Multiple Conversion Points**: Chunks → InferenceSections → SavedSearchDoc
3. **No Validation at Display Layer**: SavedSearchDoc objects aren't validated before sending to frontend

---

## ✅ Solution: Multi-Layer Validation

### Solution 1: Add Validation in `convert_inference_sections_to_search_docs` (Primary Fix)

**Location**: `backend/onyx/agents/agent_search/dr/utils.py`

**Approach**: Filter deleted user files when converting InferenceSections to SavedSearchDoc objects (before sending to frontend).

---

## 📋 Implementation

### Change 1: Update `convert_inference_sections_to_search_docs` Function

**OLD CODE**:
```python
def convert_inference_sections_to_search_docs(
    inference_sections: list[InferenceSection],
    is_internet: bool = False,
) -> list[SavedSearchDoc]:
    # Convert InferenceSections to SavedSearchDocs
    search_docs = SearchDoc.from_chunks_or_sections(inference_sections)
    for search_doc in search_docs:
        search_doc.is_internet = is_internet

    retrieved_saved_search_docs = [
        SavedSearchDoc.from_search_doc(search_doc, db_doc_id=0)
        for search_doc in search_docs
    ]
    return retrieved_saved_search_docs
```

**NEW CODE**:
```python
def convert_inference_sections_to_search_docs(
    inference_sections: list[InferenceSection],
    is_internet: bool = False,
    db_session: Session | None = None,  # ← NEW: Optional db_session for validation
) -> list[SavedSearchDoc]:
    # Convert InferenceSections to SavedSearchDocs
    search_docs = SearchDoc.from_chunks_or_sections(inference_sections)
    for search_doc in search_docs:
        search_doc.is_internet = is_internet

    # ← NEW: Filter out deleted user files if db_session is provided
    if db_session is not None:
        from onyx.db.models import UserFile
        from onyx.db.enums import UserFileStatus
        from uuid import UUID
        
        # Identify user file document IDs (UUIDs)
        user_file_doc_ids: list[tuple[SearchDoc, UUID]] = []
        other_docs: list[SearchDoc] = []
        
        for search_doc in search_docs:
            # Skip internet search docs
            if search_doc.is_internet:
                other_docs.append(search_doc)
                continue
                
            # Try to parse document_id as UUID (user files use UUID)
            try:
                user_file_id = UUID(search_doc.document_id)
                user_file_doc_ids.append((search_doc, user_file_id))
            except (ValueError, TypeError):
                # Not a UUID, so not a user file - keep it
                other_docs.append(search_doc)
        
        # If we have potential user files, validate them
        if user_file_doc_ids:
            user_file_ids = [uf_id for _, uf_id in user_file_doc_ids]
            valid_user_files = (
                db_session.query(UserFile.id)
                .filter(
                    UserFile.id.in_(user_file_ids),
                    UserFile.status != UserFileStatus.DELETING,
                )
                .all()
            )
            valid_user_file_ids = {str(uf.id) for uf in valid_user_files}
            
            # Filter: keep only valid user files
            filtered_docs = other_docs.copy()
            filtered_count = 0
            for search_doc, user_file_id in user_file_doc_ids:
                if str(user_file_id) in valid_user_file_ids:
                    filtered_docs.append(search_doc)
                else:
                    filtered_count += 1
                    logger.debug(
                        f"Filtered out deleted user_file from search results: {user_file_id} "
                        f"(document_id: {search_doc.document_id})"
                    )
            
            if filtered_count > 0:
                logger.info(
                    f"Filtered out {filtered_count} deleted user file(s) from search display"
                )
            
            search_docs = filtered_docs

    retrieved_saved_search_docs = [
        SavedSearchDoc.from_search_doc(search_doc, db_doc_id=0)
        for search_doc in search_docs
    ]
    return retrieved_saved_search_docs
```

---

### Change 2: Update Call Sites to Pass db_session

**File**: `backend/onyx/tools/tool_implementations_v2/internal_search.py`

**OLD CODE** (line 108):
```python
                            obj=SearchToolDelta(
                                type="internal_search_tool_delta",
                                queries=[],
                                documents=convert_inference_sections_to_search_docs(
                                    retrieved_sections, is_internet=False
                                ),
                            ),
```

**NEW CODE**:
```python
                            obj=SearchToolDelta(
                                type="internal_search_tool_delta",
                                queries=[],
                                documents=convert_inference_sections_to_search_docs(
                                    retrieved_sections, 
                                    is_internet=False,
                                    db_session=search_db_session  # ← NEW: Pass db_session
                                ),
                            ),
```

---

### Change 3: Update Other Call Sites

**File**: `backend/onyx/agents/agent_search/dr/sub_agents/basic_search/dr_basic_search_2_act.py`

**OLD CODE**:
```python
documents=convert_inference_sections_to_search_docs(
    doc_list
)
```

**NEW CODE**:
```python
documents=convert_inference_sections_to_search_docs(
    doc_list,
    db_session=run_context.context.run_dependencies.db_session  # ← NEW
)
```

**File**: `backend/onyx/chat/turn/save_turn.py`

**OLD CODE**:
```python
retrieved_search_docs = convert_inference_sections_to_search_docs(
    unordered_fetched_inference_sections
)
```

**NEW CODE**:
```python
retrieved_search_docs = convert_inference_sections_to_search_docs(
    unordered_fetched_inference_sections,
    db_session=db_session  # ← NEW
)
```

**Note**: For other call sites, pass `db_session=None` if not available (validation will be skipped, but existing validation in search_runner.py will still apply).

---

## 🎯 Why This Solution Works

### Defense in Depth

```
Layer 1: Search Validation (search_runner.py)
  ↓ Filters chunks from deleted files
  ↓
Layer 2: Display Validation (convert_inference_sections_to_search_docs)
  ↓ Filters SavedSearchDoc from deleted files
  ↓
Frontend: Only valid files displayed ✓
```

### Benefits

1. **Catches Race Conditions**: Even if chunks pass first validation, second validation catches them
2. **Validates at Display Layer**: Ensures deleted files never reach frontend
3. **Backward Compatible**: `db_session` is optional, existing code still works
4. **Minimal Performance Impact**: Only validates user files (UUIDs), skips connector documents

---

## 🧪 Testing

### Test Case 1: Deleted File in Thinking Window

```
1. Upload file "test.pdf"
2. Wait for indexing
3. Delete "test.pdf"
4. Upload file "new.pdf"
5. Ask question: "What is in the documents?"
6. Check thinking window
   → Should NOT show "test.pdf" ✓
   → Should show "new.pdf" ✓
```

### Test Case 2: Multiple Files

```
1. Upload files A, B, C
2. Delete file B
3. Ask question
4. Check thinking window
   → Should show A and C ✓
   → Should NOT show B ✓
```

### Test Case 3: Internet Search (Should Not Break)

```
1. Perform internet search
2. Check thinking window
   → Should show web results ✓
   → Should not error ✓
```

---

## 📊 Expected Impact

### Before Fix
- ❌ Deleted files appear in thinking window
- ❌ Users confused by seeing deleted files
- ❌ Race conditions allow deleted files through

### After Fix
- ✅ Deleted files filtered from thinking window
- ✅ Only valid files displayed
- ✅ Double validation prevents race conditions
- ✅ Better user experience

---

## 🔗 Related Files

- `onyx-repo/backend/onyx/agents/agent_search/dr/utils.py` - Main conversion function
- `onyx-repo/backend/onyx/tools/tool_implementations_v2/internal_search.py` - Internal search tool
- `onyx-repo/backend/onyx/context/search/retrieval/search_runner.py` - Search validation (existing fix)
- `onyx-repo/web/src/app/chat/message/messageComponents/renderers/SearchToolRenderer.tsx` - Frontend display

---

## 📝 Summary

**Problem**: Deleted files appear in thinking window during search.

**Root Cause**: Validation happens in search layer, but not in display layer where SavedSearchDoc objects are created.

**Solution**: Add validation in `convert_inference_sections_to_search_docs` to filter deleted user files before sending to frontend.

**Implementation**: 
1. Add optional `db_session` parameter
2. Filter user files with DELETING status
3. Update call sites to pass db_session

**Result**: Deleted files never appear in thinking window, even if Vespa deletion is delayed.

---

**Last Updated**: 2024  
**Author**: Onyx Deployment Team  
**Version**: 1.0

