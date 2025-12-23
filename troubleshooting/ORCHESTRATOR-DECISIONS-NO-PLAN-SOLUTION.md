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

---

## 🏗️ Architecture Diagrams

### **Diagram 1: Old Workflow (Before Fix) - Error Flow**

```
┌─────────────────────────────────────────────────────────────────┐
│                    USER ASKS QUESTION                           │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              ORCHESTRATOR NODE (dr_a1_orchestrator.py)          │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 1: Prepare Orchestrator Prompt                    │  │
│  │  - decision_system_prompt                                │  │
│  │  - decision_prompt                                        │  │
│  │  - uploaded_image_context                                │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 2: Call invoke_llm_json()                          │  │
│  │  - llm: graph_config.tooling.primary_llm                 │  │
│  │  - schema: OrchestratorDecisonsNoPlan                    │  │
│  │  - timeout_override: TF_DR_TIMEOUT_SHORT/LONG            │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│         LLM SERVICE (vLLM / OpenAI / etc.)                      │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  LLM Processing...                                       │  │
│  │  - May timeout                                           │  │
│  │  - May return empty response                             │  │
│  │  - May return invalid JSON                               │  │
│  │  - May return truncated response                         │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│    RESPONSE SCENARIOS (Any of these can happen):                │
│                                                                   │
│  ❌ Scenario A: Empty Response                                 │
│     ""                                                           │
│                                                                   │
│  ❌ Scenario B: Invalid JSON                                     │
│     "ROF" or "ERROR" or random text                             │
│                                                                   │
│  ❌ Scenario C: Truncated JSON                                  │
│     '{"reasoning": "The user is asking..."' (missing closing)   │
│                                                                   │
│  ❌ Scenario D: Non-JSON Text                                   │
│     "I cannot process this request at this time..."            │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│    invoke_llm_json() in llm.py                                  │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 1: Extract JSON from response                     │  │
│  │  - Try to find JSON block                                │  │
│  │  - Try to extract between { and }                       │  │
│  │  - If nothing found: response_content = ""              │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 2: Validate response_content                       │  │
│  │  - Check if empty: raise ValueError                      │  │
│  │  - OR try to parse JSON                                  │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 3: Parse with Pydantic                            │  │
│  │  schema.model_validate_json(response_content)            │  │
│  │  ❌ FAILS: ValidationError raised                        │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│    ORCHESTRATOR ERROR HANDLING (OLD CODE)                       │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  try:                                                    │  │
│  │      orchestrator_action = invoke_llm_json(...)          │  │
│  │      ...                                                 │  │
│  │  except Exception as e:  ❌ TOO BROAD                   │  │
│  │      logger.error(f"Error: {e}")                        │  │
│  │      raise e  ❌ RE-RAISES ERROR                         │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ERROR PROPAGATES UP                           │
│                                                                   │
│  ValueError / ValidationError bubbles up through:                │
│  - Orchestrator node                                             │
│  - Graph execution                                               │
│  - API handler                                                   │
│  - User interface                                                │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│              USER SEES ERROR MESSAGE                              │
│                                                                   │
│  ❌ "OrchestratorDecisionsNoPlan"                                │
│  ❌ "1 validation error for OrchestratorDecisonsNoPlan"          │
│  ❌ "Invalid JSON: EOF while parsing..."                        │
│                                                                   │
│  Result: User gets NO ANSWER, system FAILS                       │
└─────────────────────────────────────────────────────────────────┘
```

---

### **Diagram 2: New Workflow (After Fix) - Success Flow**

```
┌─────────────────────────────────────────────────────────────────┐
│                    USER ASKS QUESTION                           │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              ORCHESTRATOR NODE (dr_a1_orchestrator.py)          │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 1: Prepare Orchestrator Prompt                    │  │
│  │  - decision_system_prompt                                │  │
│  │  - decision_prompt                                        │  │
│  │  - uploaded_image_context                                │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 2: Call invoke_llm_json()                          │  │
│  │  - llm: graph_config.tooling.primary_llm                 │  │
│  │  - schema: OrchestratorDecisonsNoPlan                    │  │
│  │  - timeout_override: TF_DR_TIMEOUT_SHORT/LONG            │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│         LLM SERVICE (vLLM / OpenAI / etc.)                      │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  LLM Processing...                                       │  │
│  │  ✅ Returns valid JSON response                          │  │
│  │  {                                                       │  │
│  │    "reasoning": "...",                                  │  │
│  │    "next_step": {                                       │  │
│  │      "tool": "search",                                  │  │
│  │      "questions": ["..."]                                │  │
│  │    }                                                     │  │
│  │  }                                                       │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│    invoke_llm_json() in llm.py                                  │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 1: Extract JSON from response                     │  │
│  │  ✅ Valid JSON found                                     │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 2: Parse with Pydantic                            │  │
│  │  schema.model_validate_json(response_content)            │  │
│  │  ✅ SUCCESS: OrchestratorDecisonsNoPlan object created  │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│    ORCHESTRATOR PROCESSES RESULT                                 │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  orchestrator_action = invoke_llm_json(...)              │  │
│  │  ✅ Success - no exception raised                         │  │
│  │                                                           │  │
│  │  next_step = orchestrator_action.next_step               │  │
│  │  next_tool_name = next_step.tool                         │  │
│  │  query_list = next_step.questions                        │  │
│  │                                                           │  │
│  │  tool_calls_string = create_tool_call_string(...)        │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│              CONTINUE WITH SELECTED TOOL                         │
│                                                                   │
│  ✅ System proceeds with:                                        │
│  - Search tool                                                   │
│  - Answer tool                                                   │
│  - Or other selected tool                                        │
│                                                                   │
│  Result: User gets ANSWER                                        │
└─────────────────────────────────────────────────────────────────┘
```

---

### **Diagram 3: New Workflow (After Fix) - Error Recovery Flow**

```
┌─────────────────────────────────────────────────────────────────┐
│                    USER ASKS QUESTION                           │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              ORCHESTRATOR NODE (dr_a1_orchestrator.py)          │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 1: Prepare Orchestrator Prompt                    │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 2: Call invoke_llm_json()                          │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│         LLM SERVICE (vLLM / OpenAI / etc.)                      │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  LLM Processing...                                       │  │
│  │  ❌ PROBLEM OCCURS:                                       │  │
│  │  - Timeout                                               │  │
│  │  - Empty response                                        │  │
│  │  - Invalid JSON                                          │  │
│  │  - Truncated response                                    │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│    invoke_llm_json() in llm.py                                  │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 1: Extract JSON from response                     │  │
│  │  ❌ No valid JSON found                                   │  │
│  │  response_content = "" or invalid                        │  │
│  └──────────────────────┬───────────────────────────────────┘  │
│                         │                                       │
│                         ▼                                       │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Step 2: Validate response_content                       │  │
│  │  ❌ Empty or invalid: raise ValueError                   │  │
│  │  OR                                                       │  │
│  │  Step 3: Parse with Pydantic                            │  │
│  │  ❌ FAILS: ValidationError raised                        │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│    ORCHESTRATOR ERROR HANDLING (NEW CODE)                       │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  try:                                                    │  │
│  │      orchestrator_action = invoke_llm_json(...)         │  │
│  │      ...                                                 │  │
│  │                                                           │  │
│  │  except (ValueError, ValidationError) as e:  ✅ SPECIFIC │  │
│  │      error_msg = str(e).lower()                         │  │
│  │                                                           │  │
│  │      if (error detection):  ✅ CHECK ERROR TYPE          │  │
│  │          logger.warning(...)  ✅ LOG WARNING             │  │
│  │                                                           │  │
│  │          # FALLBACK MECHANISM ✅                         │  │
│  │          next_tool_name = DRPath.CLOSER.value            │  │
│  │          query_list = ["Answer with available info"]    │  │
│  │          tool_calls_string = create_tool_call_string(...)│  │
│  │          reasoning_result = "Unable to determine..."    │  │
│  │                                                           │  │
│  │      else:                                               │  │
│  │          logger.error(...)                               │  │
│  │          raise e  ❌ Re-raise non-JSON errors           │  │
│  └──────────────────────┬───────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│              FALLBACK TO SAFE DEFAULT                             │
│                                                                   │
│  ✅ System uses CLOSER tool:                                     │
│  - next_tool_name = "closer"                                    │
│  - query_list = ["Answer the question with the information      │
│                   you have."]                                    │
│  - reasoning_result = "Unable to determine next step from       │
│                       LLM response. Proceeding with answer        │
│                       generation."                                │
│                                                                   │
│  ✅ System continues processing instead of crashing             │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│              CONTINUE WITH CLOSER TOOL                           │
│                                                                   │
│  ✅ System proceeds with:                                        │
│  - Answer generation using available information                │
│  - No additional search needed                                  │
│  - User gets an answer based on existing context                │
│                                                                   │
│  Result: User gets ANSWER (may be limited but still works) ✅    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📋 Detailed Explanation of New Workflow

### **Phase 1: Initial Request Processing**

1. **User submits question** → Frontend sends request to backend API
2. **Orchestrator node activated** → Graph execution reaches `orchestrator()` function
3. **Prompt preparation** → System builds orchestrator prompt with:
   - Decision system prompt (instructions for LLM)
   - Decision prompt (context about current state)
   - Uploaded image context (if any)
   - Question history, answer history, chat history

### **Phase 2: LLM Invocation**

4. **Call `invoke_llm_json()`** → Orchestrator calls LLM with:
   - **LLM instance**: `graph_config.tooling.primary_llm`
   - **Schema**: `OrchestratorDecisonsNoPlan` (Pydantic model)
   - **Timeout**: `TF_DR_TIMEOUT_SHORT` (BROAD) or `TF_DR_TIMEOUT_LONG` (DEEP)

5. **LLM processing** → LLM service processes request:
   - May return valid JSON ✅
   - May timeout ❌
   - May return empty response ❌
   - May return invalid JSON ❌

### **Phase 3: Response Processing (in `invoke_llm_json`)**

6. **JSON extraction** → `invoke_llm_json()` tries to extract JSON:
   - If model supports structured outputs: Uses native JSON mode
   - Otherwise: Tries regex pattern matching or bracket extraction
   - If nothing found: `response_content = ""`

7. **Validation** → Checks if response is valid:
   - **Empty check**: If `response_content` is empty → raises `ValueError`
   - **JSON parsing**: Tries `schema.model_validate_json()`
   - **On failure**: Raises `ValidationError` (Pydantic)

### **Phase 4: Error Handling (NEW - Key Improvement)**

8. **Exception catching** → Orchestrator catches specific exceptions:
   ```python
   except (ValueError, ValidationError) as e:
   ```
   - **Why specific?** Only catches JSON parsing errors, not all errors
   - **Why both?** `ValueError` from empty response check, `ValidationError` from Pydantic

9. **Error detection** → Checks if error is JSON-related:
   ```python
   error_msg = str(e).lower()
   if (
       "empty response" in error_msg or
       "invalid json" in error_msg or
       "orchestratordecisonsnoplan" in error_msg or
       "validation error" in error_msg
   ):
   ```
   - **Purpose**: Distinguishes JSON errors from other errors
   - **Why important**: Other errors should still be raised

10. **Fallback mechanism** → If JSON error detected:
    ```python
    next_tool_name = DRPath.CLOSER.value
    query_list = ["Answer the question with the information you have."]
    reasoning_result = "Unable to determine next step from LLM response..."
    ```
    - **CLOSER tool**: Safe default that generates answers
    - **Default query**: Generic instruction to answer with available info
    - **Reasoning**: Documents why fallback was used

11. **Logging** → Logs warning (not error):
    ```python
    logger.warning(f"LLM returned invalid JSON, falling back to default tool...")
    ```
    - **Why warning?** System recovered, not a critical failure
    - **Why log?** Helps debug LLM issues

### **Phase 5: Continuation**

12. **Tool execution** → System continues with selected tool:
    - **Normal path**: Uses LLM's selected tool (search, answer, etc.)
    - **Fallback path**: Uses CLOSER tool to generate answer

13. **Answer generation** → System generates response:
    - Uses available context and information
    - May be limited if fallback was used
    - But user still gets an answer ✅

### **Key Differences: Old vs New**

| Aspect | Old Workflow | New Workflow |
|--------|--------------|--------------|
| **Exception Handling** | `except Exception` (too broad) | `except (ValueError, ValidationError)` (specific) |
| **Error Detection** | None - all errors raised | Checks error message for JSON issues |
| **Fallback** | None - system crashes | Falls back to CLOSER tool |
| **User Experience** | Sees error message | Gets answer (may be limited) |
| **Logging** | Error level | Warning level (recovered) |
| **System Behavior** | Stops processing | Continues processing |

### **Why This Works**

1. **Graceful degradation**: System continues working even when LLM fails
2. **User-friendly**: Users get answers instead of errors
3. **Debuggable**: Warnings help identify LLM issues
4. **Safe**: Fallback uses proven CLOSER tool
5. **Specific**: Only handles JSON errors, other errors still raised

### **When Fallback Activates**

The fallback mechanism activates when:
- ✅ LLM times out
- ✅ LLM returns empty response
- ✅ LLM returns invalid JSON
- ✅ LLM returns truncated JSON
- ✅ Pydantic validation fails

The fallback does NOT activate for:
- ❌ Network errors (different exception type)
- ❌ Authentication errors (different exception type)
- ❌ Other system errors (different exception type)

This ensures that only JSON parsing errors trigger the fallback, while other critical errors are still properly raised.

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

**OLD CODE:**
```python
try:
    orchestrator_action = invoke_llm_json(
        llm=graph_config.tooling.primary_llm,
        prompt=create_question_prompt(
            decision_system_prompt,
            decision_prompt,
            uploaded_image_context=uploaded_image_context,
        ),
        schema=OrchestratorDecisonsNoPlan,
        timeout_override=TF_DR_TIMEOUT_LONG,
        # max_tokens=1500,
    )
    next_step = orchestrator_action.next_step
    next_tool_name = next_step.tool

    query_list = [q for q in (next_step.questions or [])]
    reasoning_result = orchestrator_action.reasoning

    tool_calls_string = create_tool_call_string(next_tool_name, query_list)
except Exception as e:
    logger.error(f"Error in approach extraction: {e}")
    raise e
```

**NEW CODE:**
```python
try:
    orchestrator_action = invoke_llm_json(
        llm=graph_config.tooling.primary_llm,
        prompt=create_question_prompt(
            decision_system_prompt,
            decision_prompt,
            uploaded_image_context=uploaded_image_context,
        ),
        schema=OrchestratorDecisonsNoPlan,
        timeout_override=TF_DR_TIMEOUT_LONG,
        # max_tokens=1500,
    )
    next_step = orchestrator_action.next_step
    next_tool_name = next_step.tool

    query_list = [q for q in (next_step.questions or [])]
    reasoning_result = orchestrator_action.reasoning

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

