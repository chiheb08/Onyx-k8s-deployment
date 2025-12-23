# Solution: OrchestratorDecisionsNoPlan Error

## 🔴 Error Message

Users may see this error when asking questions:

```
OrchestratorDecisionsNoPlan
1 validation error for OrchestratorDecisonsNoPlan
Invalid JSON: EOF while parsing a value at line 1 column 0
[type=json_invalid, input_value="", input_type=str]
```

Or variations like:
- `OrchestratorDecisionsNoPlan`
- `1 validation error for OrchestratorDecisonsNoPlan`
- `Invalid JSON: ROF while parsing a value`

---

## 🔍 Root Cause

The orchestrator calls the LLM to generate a structured JSON response, but the LLM sometimes returns:

1. **Empty response** - LLM timed out or was interrupted
2. **Malformed JSON** - Response doesn't start with `{` (e.g., starts with "ROF")
3. **Truncated response** - Response cut off mid-generation
4. **Non-JSON text** - LLM returns explanatory text instead of JSON

**Why this happens:**
- LLM timeout or interruption
- LLM server overload
- Network issues causing incomplete response
- Model not following JSON format instructions
- vLLM server returning error instead of completion

---

## ✅ Solution Implemented

### **What Was Fixed**

**File:** `onyx-repo/backend/onyx/agents/agent_search/dr/nodes/dr_a1_orchestrator.py`

**Changes Made:**

1. **Added ValidationError import** (line 44)
   ```python
   from pydantic import ValidationError
   ```

2. **Improved error handling in BROAD research** (lines 353-375)
   - Catches `ValueError` and `ValidationError` specifically
   - Detects JSON parsing errors
   - Falls back to safe default behavior instead of crashing

3. **Improved error handling in DEEP research** (lines 484-506)
   - Same improvements as BROAD research
   - Ensures consistency across both research types

### **How It Works Now**

**Before (Old Behavior):**
```
LLM returns invalid JSON
  ↓
invoke_llm_json raises ValueError
  ↓
Orchestrator catches Exception and re-raises
  ↓
User sees error: "OrchestratorDecisionsNoPlan" ❌
```

**After (New Behavior):**
```
LLM returns invalid JSON
  ↓
invoke_llm_json raises ValueError
  ↓
Orchestrator catches ValueError/ValidationError
  ↓
Detects it's a JSON parsing error
  ↓
Falls back to CLOSER tool (safe default)
  ↓
System continues working ✅
```

---

## 📝 Code Changes Details

### **Location 1: BROAD Research (around line 333)**

**OLD CODE:**
```python
try:
    orchestrator_action = invoke_llm_json(...)
    next_step = orchestrator_action.next_step
    next_tool_name = next_step.tool
    query_list = [q for q in (next_step.questions or [])]
    tool_calls_string = create_tool_call_string(next_tool_name, query_list)

except Exception as e:
    logger.error(f"Error in approach extraction: {e}")
    raise e
```

**NEW CODE:**
```python
try:
    orchestrator_action = invoke_llm_json(...)
    next_step = orchestrator_action.next_step
    next_tool_name = next_step.tool
    query_list = [q for q in (next_step.questions or [])]
    tool_calls_string = create_tool_call_string(next_tool_name, query_list)

except (ValueError, ValidationError) as e:
    # Handle JSON parsing errors and validation errors gracefully
    error_msg = str(e).lower()
    if (
        "empty response" in error_msg
        or "invalid json" in error_msg
        or "orchestratordecisonsnoplan" in error_msg
        or "validation error" in error_msg
    ):
        logger.warning(
            f"LLM returned invalid JSON for orchestrator decision, falling back to default tool. Error: {e}"
        )
        # Fallback to a safe default - use CLOSER tool to answer with available information
        next_tool_name = DRPath.CLOSER.value
        query_list = ["Answer the question with the information you have."]
        tool_calls_string = create_tool_call_string(next_tool_name, query_list)
        reasoning_result = "Unable to determine next step from LLM response. Proceeding with answer generation."
    else:
        logger.error(f"Error in approach extraction: {e}")
        raise e
except Exception as e:
    logger.error(f"Error in approach extraction: {e}")
    raise e
```

### **Location 2: DEEP Research (around line 464)**

Same changes applied to the DEEP research path.

---

## 🎯 What This Fix Does

1. **Catches JSON Parsing Errors**
   - Specifically handles `ValueError` and `ValidationError`
   - Detects common error patterns in error messages

2. **Graceful Fallback**
   - Instead of crashing, falls back to `CLOSER` tool
   - Uses safe default query: "Answer the question with the information you have."
   - System continues to work, user gets an answer

3. **Better Logging**
   - Logs warnings instead of errors for recoverable issues
   - Helps with debugging while not alarming users

4. **User Experience**
   - Users no longer see cryptic error messages
   - System continues working even when LLM has issues
   - Answers are still generated using available information

---

## 🧪 Testing

### **Test Scenarios**

1. **Normal Operation**
   - ✅ Should work as before when LLM returns valid JSON

2. **LLM Timeout**
   - ✅ Should fall back gracefully instead of showing error

3. **Invalid JSON Response**
   - ✅ Should fall back gracefully instead of crashing

4. **Empty Response**
   - ✅ Should fall back gracefully instead of showing error

### **How to Verify**

1. **Check Logs**
   ```bash
   # Look for warning messages about fallback
   kubectl logs <backend-pod> | grep -i "falling back to default tool"
   ```

2. **Test with Complex Query**
   - Ask a complex question that might cause LLM timeout
   - System should still respond (may use fallback)

3. **Monitor Error Rates**
   - Before fix: Users see "OrchestratorDecisionsNoPlan" errors
   - After fix: System continues working, fewer user-facing errors

---

## 🔧 Troubleshooting

### **If Error Still Occurs**

1. **Check LLM Configuration**
   - Verify LLM timeout settings
   - Check if LLM server is responding
   - Verify network connectivity

2. **Check Logs**
   ```bash
   # Check for LLM errors
   kubectl logs <backend-pod> | grep -i "orchestrator\|llm\|json"
   
   # Check for fallback messages
   kubectl logs <backend-pod> | grep -i "falling back"
   ```

3. **Verify Code Changes**
   - Ensure changes are deployed
   - Check that `ValidationError` is imported
   - Verify both BROAD and DEEP paths are updated

### **If Fallback Happens Too Often**

1. **Investigate LLM Issues**
   - Check LLM server health
   - Review timeout settings
   - Check for model server overload

2. **Review Error Patterns**
   - Look at logs to see what errors trigger fallback
   - May indicate underlying LLM configuration issues

---

## 📊 Impact

### **Before Fix**
- ❌ Users see cryptic error: "OrchestratorDecisionsNoPlan"
- ❌ System crashes on JSON parsing errors
- ❌ No answer provided to user
- ❌ Poor user experience

### **After Fix**
- ✅ System continues working even with LLM issues
- ✅ Users get answers (may use fallback)
- ✅ Better error logging for debugging
- ✅ Improved user experience

---

## 🔗 Related Files

- `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py` - JSON parsing logic
- `onyx-repo/backend/onyx/agents/agent_search/dr/models.py` - Schema definitions
- `onyx-k8s-infrastructure/troubleshooting/ORCHESTRATOR-JSON-PARSING-ERROR.md` - Original error documentation
- `onyx-k8s-infrastructure/troubleshooting/ORCHESTRATOR-JSON-ERROR-FIX.md` - Previous fix attempt

---

## 📝 Summary

**Problem:** OrchestratorDecisionsNoPlan error when LLM returns invalid JSON

**Solution:** Added graceful error handling with fallback mechanism

**Result:** System continues working even when LLM has issues, better user experience

**Files Modified:**
- `onyx-repo/backend/onyx/agents/agent_search/dr/nodes/dr_a1_orchestrator.py`

**Status:** ✅ Fixed and deployed

