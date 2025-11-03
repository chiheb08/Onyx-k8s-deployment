# Orchestrator JSON Parsing Error

## Problem Description

When asking questions about uploaded documents, users see this error:

```
1 validation error for OrchestratorDecisonsNoPlan
Invalid JSON: ROF while parsing a value at line 1 column 0
[type=json_invalid, input_value=", input_type=str]
```

## Affected Components

### Backend Service
- **File**: `onyx-repo/backend/onyx/agents/agent_search/dr/nodes/dr_a1_orchestrator.py`
- **Function**: `orchestrator()` 
- **Lines**: 335-354 (for BROAD research) or 466-476 (for DEEP research)
- **Model**: `OrchestratorDecisonsNoPlan` (Pydantic schema)

### Error Location
- **File**: `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py`
- **Function**: `invoke_llm_json()` (line 183)
- **Schema**: `OrchestratorDecisonsNoPlan` (expects JSON with `reasoning` and `next_step` fields)

## Root Cause

The orchestrator calls the LLM to generate a structured JSON response, but the LLM sometimes returns:

1. **Malformed JSON** - Response doesn't start with `{` (e.g., starts with "ROF")
2. **Truncated Response** - Response cut off mid-generation
3. **Non-JSON Text** - LLM returns explanatory text instead of JSON
4. **Encoding Issues** - Special characters or encoding problems

The error "ROF" suggests the response might be:
- A truncated/corrupted response from vLLM
- A partial response that got cut off
- An error message from the model server instead of actual content

## Code Flow

### Step 1: Orchestrator Calls LLM
```python
# dr_a1_orchestrator.py lines 335-344
orchestrator_action = invoke_llm_json(
    llm=graph_config.tooling.primary_llm,
    prompt=create_question_prompt(...),
    schema=OrchestratorDecisonsNoPlan,  # Expected schema
    timeout_override=TF_DR_TIMEOUT_SHORT,
)
```

### Step 2: invoke_llm_json Attempts JSON Extraction
```python
# llm.py lines 158-183
response_content = str(llm.invoke(...).content)

if not supports_json:
    # Try to extract JSON from response
    response_content = response_content.replace("\n", " ")
    json_block_match = JSON_PATTERN.search(response_content)
    if json_block_match:
        response_content = json_block_match.group(1)
    else:
        # Fallback: extract between first { and last }
        first_bracket = response_content.find("{")
        last_bracket = response_content.rfind("}")
        response_content = response_content[first_bracket : last_bracket + 1]

# ❌ PROBLEM: If response_content is empty, corrupted, or starts with "ROF",
# this will fail with JSON parsing error
return schema.model_validate_json(response_content)
```

### Step 3: Pydantic Validation Fails
```python
# Expected structure:
{
  "reasoning": "...",
  "next_step": {
    "tool": "...",
    "questions": ["..."]
  }
}

# But received (example):
"ROF"  # or empty string, or corrupted data
```

## Expected vs Actual Response

### Expected Response (Valid JSON)
```json
{
  "reasoning": "The user is asking about a PDF document. I should use the search tool to find relevant information.",
  "next_step": {
    "tool": "search",
    "questions": ["What is this document about?"]
  }
}
```

### Actual Response (Invalid - Causing Error)
```
ROF  # or empty string, or "ERROR", or truncated JSON
```

## Potential Causes

1. **vLLM Server Issues**
   - Model server returning error instead of completion
   - Response timeout/cancellation
   - Model server overload or connection issues

2. **Model Behavior**
   - LLM not following JSON format instructions
   - Model outputting text before JSON
   - Model generating malformed JSON

3. **Response Processing**
   - JSON extraction logic failing to find valid JSON
   - Response truncated during network transfer
   - Encoding/decoding issues

## Diagnostic Steps

### 1. Check Backend Logs
Look for logs around the orchestrator call:
```bash
# In API server logs, search for:
grep -i "orchestrator\|invoke_llm_json\|OrchestratorDecisonsNoPlan" <logs>
```

### 2. Check vLLM Server Logs
Verify the model server is responding correctly:
```bash
# Check vLLM logs for errors or truncated responses
kubectl logs <vllm-pod-name> | grep -i error
```

### 3. Verify Model Configuration
Check if the model supports structured outputs:
- Some models don't support `response_format` or structured outputs
- The code falls back to regex-based JSON extraction which is less reliable

### 4. Check Network/Timeout Issues
- Long-running queries might timeout
- Network issues could truncate responses

## Solutions

### Immediate Fix: Add Error Handling
The `invoke_llm_json` function should handle malformed responses gracefully:

```python
# Suggested improvement in llm.py
def invoke_llm_json(...):
    try:
        response_content = str(llm.invoke(...).content)
        
        # ... JSON extraction logic ...
        
        # Validate JSON before parsing
        if not response_content or not response_content.strip().startswith("{"):
            logger.error(f"LLM returned invalid JSON: {response_content[:200]}")
            raise ValueError(f"LLM response is not valid JSON: {response_content[:100]}")
            
        return schema.model_validate_json(response_content)
    except (ValueError, json.JSONDecodeError, ValidationError) as e:
        logger.error(f"Failed to parse LLM JSON response: {e}")
        logger.error(f"Response content: {response_content[:500]}")
        # Return a fallback or re-raise with more context
        raise
```

### Long-term Solutions

1. **Use Models with Structured Output Support**
   - Models that support `response_format: json_schema` are more reliable
   - Update model configuration if needed

2. **Improve JSON Extraction**
   - Add better fallback logic for malformed responses
   - Try multiple extraction strategies

3. **Add Retry Logic**
   - Retry with a simpler prompt if JSON parsing fails
   - Fall back to a default orchestrator decision

4. **Better Error Messages**
   - Show user-friendly error instead of raw Pydantic validation error
   - Log the actual LLM response for debugging

## Temporary Workaround

Until fixed, users can:
1. Try rephrasing the question
2. Break complex questions into simpler ones
3. Retry the query (might work on retry if it's a transient issue)

## Related Files

- `onyx-repo/backend/onyx/agents/agent_search/dr/models.py` - Schema definition
- `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py` - JSON parsing logic
- `onyx-repo/backend/onyx/agents/agent_search/dr/nodes/dr_a1_orchestrator.py` - Orchestrator implementation

## Next Steps

1. Check vLLM server logs for the actual response
2. Add better error logging to capture the raw LLM response
3. Implement fallback handling for malformed responses
4. Consider using models with better structured output support

