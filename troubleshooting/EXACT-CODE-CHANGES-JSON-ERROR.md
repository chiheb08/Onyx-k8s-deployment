# Exact Code Changes: User-Friendly JSON Error Messages

## 📁 File 1: `llm.py`

**File Path:** `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py`

**Location:** Inside the `invoke_llm_json` function (around lines 190-210)

---

### **Change 1: Empty Response Error Message**

**📍 WHERE TO FIND IT:**
- Look for the section that checks `if not response_content or not response_content.strip():`
- This should be around **line 190-201**

**✏️ EXACT CHANGE:**

**--- OLD CODE (Lines 197-201) ---**
```python
        raise ValueError(
            f"LLM returned empty response when JSON was expected. "
            f"This usually means the LLM timed out, was interrupted, or failed to generate a response. "
            f"Please try again or check your LLM configuration."
        )
```

**--- NEW CODE (Replace with this) ---**
```python
        raise ValueError(
            "The AI system is taking longer than expected to process your request. "
            "This usually happens when the system is busy or your request is very complex. "
            "Please wait a moment and try again. If the problem continues, try simplifying your question or contact support."
        )
```

**📝 STEP-BY-STEP:**
1. Find the line that says `raise ValueError(`
2. Find the error message inside the parentheses
3. Replace the entire `raise ValueError(...)` block with the new code above
4. Make sure the indentation matches (should be 8 spaces)

---

### **Change 2: JSON Parsing Error Message**

**📍 WHERE TO FIND IT:**
- Look for the `try:` block that contains `return schema.model_validate_json(response_content)`
- Look for the `except Exception as e:` block right after it
- This should be around **line 203-210**

**✏️ EXACT CHANGE:**

**--- OLD CODE (Lines 203-210) ---**
```python
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

**--- NEW CODE (Replace with this) ---**
```python
    try:
        return schema.model_validate_json(response_content)
    except Exception as e:
        logger.error(
            f"Failed to parse LLM JSON response. Response content (first 200 chars): {response_content[:200]}... "
            f"Error: {e}"
        )
        # Provide user-friendly error message
        raise ValueError(
            "The AI system encountered an issue processing your request. "
            "This can happen when the system is busy or your request is very complex. "
            "Please try again in a moment. If the problem continues, try rephrasing your question or contact support."
        ) from e
```

**📝 STEP-BY-STEP:**
1. Find the `try:` block with `return schema.model_validate_json(response_content)`
2. Find the `except Exception as e:` block right after it
3. Find the `raise ValueError(` inside the except block
4. Replace the entire `raise ValueError(...)` block with the new code above
5. Add the comment `# Provide user-friendly error message` before the raise statement

---

## 📁 File 2: `utils.py`

**File Path:** `onyx-repo/backend/onyx/llm/utils.py`

**Location:** Inside the `litellm_exception_to_error_msg` function (around lines 175-184)

---

### **Change: Add ValueError Handling**

**📍 WHERE TO FIND IT:**
- Look for the end of the `litellm_exception_to_error_msg` function
- Find the section that says `elif not fallback_to_error_msg:`
- This should be around **line 182-184**

**✏️ EXACT CHANGE:**

**--- OLD CODE (Lines 182-184) ---**
```python
    elif not fallback_to_error_msg:
        error_msg = "An unexpected error occurred while processing your request. Please try again later."
    return error_msg
```

**--- NEW CODE (Replace with this) ---**
```python
    elif isinstance(core_exception, ValueError):
        # Check for specific error patterns and provide user-friendly messages
        error_str = str(core_exception).lower()
        
        if "empty response" in error_str or "invalid json" in error_str or "eof" in error_str or "taking longer" in error_str:
            error_msg = (
                "The AI system is taking longer than expected to process your request. "
                "This usually happens when the system is busy or your request is very complex. "
                "Please wait a moment and try again. If the problem continues, try simplifying your question."
            )
        elif "timeout" in error_str:
            error_msg = (
                "Your request took too long to process. "
                "This can happen with complex questions or when the system is busy. "
                "Please try again or simplify your question."
            )
        elif "failed to parse" in error_str or "encountered an issue" in error_str:
            error_msg = (
                "The AI system encountered an issue processing your request. "
                "Please try again in a moment. If the problem continues, try rephrasing your question."
            )
        elif not fallback_to_error_msg:
            error_msg = "An unexpected error occurred while processing your request. Please try again later."
        else:
            error_msg = str(core_exception)
    elif not fallback_to_error_msg:
        error_msg = "An unexpected error occurred while processing your request. Please try again later."
    return error_msg
```

**📝 STEP-BY-STEP:**
1. Find the line that says `elif not fallback_to_error_msg:`
2. Find the line that says `return error_msg` (this is the last line of the function)
3. **BEFORE** the `elif not fallback_to_error_msg:` line, add the new `elif isinstance(core_exception, ValueError):` block
4. Keep the existing `elif not fallback_to_error_msg:` block after the new ValueError block
5. Make sure the indentation matches (should be 4 spaces for the `elif`)

---

## 📊 Complete Code Sections (For Reference)

### **File 1: `llm.py` - Complete Section After Changes**

**Location:** Lines 190-215

```python
    # Validate that we have content before parsing
    if not response_content or not response_content.strip():
        logger.error(
            f"LLM returned empty or invalid JSON response. "
            f"Model: {llm.config.model_name}, Provider: {llm.config.model_provider}. "
            f"This usually means the LLM timed out, was interrupted, or failed to generate a response."
        )
        raise ValueError(
            "The AI system is taking longer than expected to process your request. "
            "This usually happens when the system is busy or your request is very complex. "
            "Please wait a moment and try again. If the problem continues, try simplifying your question or contact support."
        )

    try:
        return schema.model_validate_json(response_content)
    except Exception as e:
        logger.error(
            f"Failed to parse LLM JSON response. Response content (first 200 chars): {response_content[:200]}... "
            f"Error: {e}"
        )
        # Provide user-friendly error message
        raise ValueError(
            "The AI system encountered an issue processing your request. "
            "This can happen when the system is busy or your request is very complex. "
            "Please try again in a moment. If the problem continues, try rephrasing your question or contact support."
        ) from e
```

### **File 2: `utils.py` - Complete Section After Changes**

**Location:** Lines 175-210 (end of function)

```python
    elif isinstance(core_exception, Timeout):
        error_msg = "Request timed out: The operation took too long to complete. Please try again."
    elif isinstance(core_exception, APIError):
        error_msg = (
            "API error: An error occurred while communicating with the API. "
            f"Details: {str(core_exception)}"
        )
    elif isinstance(core_exception, ValueError):
        # Check for specific error patterns and provide user-friendly messages
        error_str = str(core_exception).lower()
        
        if "empty response" in error_str or "invalid json" in error_str or "eof" in error_str or "taking longer" in error_str:
            error_msg = (
                "The AI system is taking longer than expected to process your request. "
                "This usually happens when the system is busy or your request is very complex. "
                "Please wait a moment and try again. If the problem continues, try simplifying your question."
            )
        elif "timeout" in error_str:
            error_msg = (
                "Your request took too long to process. "
                "This can happen with complex questions or when the system is busy. "
                "Please try again or simplify your question."
            )
        elif "failed to parse" in error_str or "encountered an issue" in error_str:
            error_msg = (
                "The AI system encountered an issue processing your request. "
                "Please try again in a moment. If the problem continues, try rephrasing your question."
            )
        elif not fallback_to_error_msg:
            error_msg = "An unexpected error occurred while processing your request. Please try again later."
        else:
            error_msg = str(core_exception)
    elif not fallback_to_error_msg:
        error_msg = "An unexpected error occurred while processing your request. Please try again later."
    return error_msg
```

---

## ✅ Verification Checklist

After making changes, verify:

### **File 1: `llm.py`**
- [ ] ✅ Line 197-201: Empty response error message is user-friendly
- [ ] ✅ Line 203-210: JSON parsing error message is user-friendly
- [ ] ✅ Comment added: `# Provide user-friendly error message`
- [ ] ✅ Indentation is correct (8 spaces for raise statements)

### **File 2: `utils.py`**
- [ ] ✅ ValueError handling block added before `elif not fallback_to_error_msg:`
- [ ] ✅ Error pattern matching checks for "empty response", "invalid json", "eof", "taking longer"
- [ ] ✅ Indentation is correct (4 spaces for elif blocks)
- [ ] ✅ `return error_msg` is still the last line

---

## 🧪 Testing

After making changes:

1. **Test with a prompt that previously failed:**
   - Send a complex question
   - If error occurs, verify user-friendly message appears

2. **Check the error message:**
   - Should NOT contain: "Invalid JSON", "EOF", "parsing a value"
   - Should contain: "AI system", "try again", "simplifying your question"

3. **Test normal prompts:**
   - Should work as before (no changes to normal flow)

---

## 📝 Summary

**File 1 Changes:**
- ✅ Replace empty response error message (lines 197-201)
- ✅ Replace JSON parsing error message (lines 207-210)

**File 2 Changes:**
- ✅ Add ValueError handling block (before line 182)

**Result:**
- ✅ Users see helpful messages instead of technical errors
- ✅ Clear guidance on what to do
- ✅ Better user experience

---

That's it! Make these exact changes and users will see friendly error messages. 🎉


