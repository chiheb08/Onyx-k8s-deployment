# Fix: Orchestrator JSON Parsing Error

## 🔴 Error Message

```
1 validation error for OrchestratorDecisonsNoPlan
Invalid JSON: EOF while parsing a value at line 1 column 0
[type=json_invalid, input_value="", input_type=str]
```

## 🔍 Root Cause

The LLM is returning an **empty or invalid JSON response** when the orchestrator tries to decide the next step. The `invoke_llm_json` function receives an empty string and fails to parse it.

**Why this happens:**
- LLM timeout or interruption
- LLM returns empty response
- LLM returns non-JSON text
- Network issues causing incomplete response

---

## ✅ Solution: Add Error Handling

**File:** `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py`

**Location:** `invoke_llm_json` function (around line 137-183)

---

## 📝 Step-by-Step Fix

### **Step 1: Open the File**

1. Navigate to: `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py`
2. Open it in your code editor

---

### **Step 2: Find the `invoke_llm_json` Function**

**📍 WHERE TO FIND IT:**
- Look for function `def invoke_llm_json(` (around line 137)
- This function calls the LLM and parses JSON responses

---

### **Step 3: Add Error Handling for Empty Responses**

**📍 WHERE TO ADD IT:**
- Right before the line `return schema.model_validate_json(response_content)` (around line 183)
- After the JSON extraction logic

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
            if first_bracket != -1 and last_bracket != -1:
                response_content = response_content[first_bracket : last_bracket + 1]
            else:
                # No JSON found in response
                response_content = ""

    # Validate that we have content before parsing
    if not response_content or not response_content.strip():
        logger.error(
            f"LLM returned empty or invalid JSON response. "
            f"Original response length: {len(str(llm.invoke(prompt, timeout_override=timeout_override, max_tokens=max_tokens).content)))}"
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
            f"Failed to parse LLM JSON response. Response content: {response_content[:200]}... "
            f"Error: {e}"
        )
        raise ValueError(
            f"Failed to parse LLM response as JSON. The LLM may have returned invalid JSON. "
            f"Original error: {str(e)}"
        ) from e
```

**📝 DETAILED INSTRUCTIONS:**

1. **Find the line:** `return schema.model_validate_json(response_content)`
2. **Before that line**, add validation for empty responses
3. **Wrap the return** in a try-except block for better error messages
4. **Add logging** to help debug the issue

---

## 🔧 Complete Code Section (For Reference)

Here's what the complete `invoke_llm_json` function should look like:

```python
def invoke_llm_json(
    llm: LLM,
    prompt: LanguageModelInput,
    schema: Type[SchemaType],
    tools: list[dict] | None = None,
    tool_choice: ToolChoiceOptions | None = None,
    timeout_override: int | None = None,
    max_tokens: int | None = None,
) -> SchemaType:
    """
    Invoke an LLM, forcing it to respond in a specified JSON format if possible,
    and return an object of that schema.
    """
    from litellm.utils import get_supported_openai_params, supports_response_schema

    # check if the model supports response_format: json_schema
    supports_json = "response_format" in (
        get_supported_openai_params(llm.config.model_name, llm.config.model_provider)
        or []
    ) and supports_response_schema(llm.config.model_name, llm.config.model_provider)

    response_content = str(
        llm.invoke(
            prompt,
            tools=tools,
            tool_choice=tool_choice,
            timeout_override=timeout_override,
            max_tokens=max_tokens,
            **cast(
                dict, {"structured_response_format": schema} if supports_json else {}
            ),
        ).content
    )

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
            if first_bracket != -1 and last_bracket != -1:
                response_content = response_content[first_bracket : last_bracket + 1]
            else:
                # No JSON found in response
                response_content = ""

    # NEW: Validate that we have content before parsing
    if not response_content or not response_content.strip():
        logger.error(
            f"LLM returned empty or invalid JSON response. "
            f"Model: {llm.config.model_name}, Provider: {llm.config.model_provider}"
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
            f"Failed to parse LLM JSON response. Response content: {response_content[:200]}... "
            f"Error: {e}"
        )
        raise ValueError(
            f"Failed to parse LLM response as JSON. The LLM may have returned invalid JSON. "
            f"Original error: {str(e)}"
        ) from e
```

---

## 🎯 Alternative: Add Fallback in Orchestrator

If you want a more graceful fallback, you can also modify the orchestrator to handle this error:

**File:** `onyx-repo/backend/onyx/agents/agent_search/dr/nodes/dr_a1_orchestrator.py`

**Location:** Around lines 335-354 and 465-486 (where `invoke_llm_json` is called)

**✏️ WHAT TO CHANGE:**

**--- OLD ---**
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
                    timeout_override=TF_DR_TIMEOUT_SHORT,
                )
                next_step = orchestrator_action.next_step
                next_tool_name = next_step.tool
                query_list = [q for q in (next_step.questions or [])]

                tool_calls_string = create_tool_call_string(next_tool_name, query_list)

            except Exception as e:
                logger.error(f"Error in approach extraction: {e}")
                raise e
```

**--- NEW ---**
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
                    timeout_override=TF_DR_TIMEOUT_SHORT,
                )
                next_step = orchestrator_action.next_step
                next_tool_name = next_step.tool
                query_list = [q for q in (next_step.questions or [])]

                tool_calls_string = create_tool_call_string(next_tool_name, query_list)

            except ValueError as e:
                # Handle JSON parsing errors more gracefully
                if "empty response" in str(e).lower() or "invalid json" in str(e).lower():
                    logger.warning(
                        f"LLM returned invalid JSON, falling back to default tool. Error: {e}"
                    )
                    # Fallback to a safe default
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

**Apply the same pattern to the other `invoke_llm_json` call around line 465.**

---

## ✅ Verification Checklist

After making changes:

- [ ] ✅ Empty response validation added
- [ ] ✅ Try-except block around JSON parsing
- [ ] ✅ Error logging added
- [ ] ✅ (Optional) Fallback logic in orchestrator
- [ ] ✅ Code indentation is correct
- [ ] ✅ No syntax errors

---

## 🧪 Testing

After implementing:

1. **Test with normal prompt:**
   - Should work as before

2. **Test with timeout scenario:**
   - If LLM times out, should show better error message

3. **Check logs:**
   - Should see detailed error messages if JSON parsing fails

---

## 🐛 Troubleshooting

### **Error still occurs:**
- Check LLM configuration (timeout, max_tokens)
- Check LLM service is responding
- Check network connectivity to LLM

### **Error message not helpful:**
- Verify logging is enabled
- Check log level is set to ERROR or WARNING

---

## 📝 Summary

**What we changed:**
1. ✅ Added validation for empty responses
2. ✅ Added try-except for better error handling
3. ✅ Added detailed error logging
4. ✅ (Optional) Added fallback in orchestrator

**Result:**
- ✅ Better error messages
- ✅ More graceful handling of LLM failures
- ✅ Easier debugging

**Files Modified:**
- `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py` (required)
- `onyx-repo/backend/onyx/agents/agent_search/dr/nodes/dr_a1_orchestrator.py` (optional fallback)

