# Code Changes: Old vs New - User-Friendly Error Messages

## 📋 Overview

This document shows **exactly** what code to change, with **old code** and **new code** side-by-side.

---

## 📁 File 1: `llm.py`

**File Path:** `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py`

**Function:** `invoke_llm_json`

---

### **Change 1: Empty Response Error Message**

**📍 Location:** Around line 197-201

**--- OLD CODE ---**
```python
        raise ValueError(
            f"LLM returned empty response when JSON was expected. "
            f"This usually means the LLM timed out, was interrupted, or failed to generate a response. "
            f"Please try again or check your LLM configuration."
        )
```

**--- NEW CODE ---**
```python
        raise ValueError(
            "The AI system is taking longer than expected to process your request. "
            "This usually happens when the system is busy or your request is very complex. "
            "Please wait a moment and try again. If the problem continues, try simplifying your question or contact support."
        )
```

**📝 What Changed:**
- Removed technical details about "LLM" and "JSON"
- Changed to user-friendly language
- Added helpful guidance on what to do

---

### **Change 2: JSON Parsing Error Message**

**📍 Location:** Around line 203-215

**--- OLD CODE ---**
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

**--- NEW CODE ---**
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

**📝 What Changed:**
- Removed technical error details (`str(e)`, "invalid JSON")
- Changed to user-friendly message
- Added comment: `# Provide user-friendly error message`
- Kept the logger.error (for debugging) but changed user-facing message

---

## 📁 File 2: `utils.py`

**File Path:** `onyx-repo/backend/onyx/llm/utils.py`

**Function:** `litellm_exception_to_error_msg`

---

### **Change: Add ValueError Handling**

**📍 Location:** Around line 182-184 (before the final `elif not fallback_to_error_msg:`)

**--- OLD CODE ---**
```python
    elif isinstance(core_exception, APIError):
        error_msg = (
            "API error: An error occurred while communicating with the API. "
            f"Details: {str(core_exception)}"
        )
    elif not fallback_to_error_msg:
        error_msg = "An unexpected error occurred while processing your request. Please try again later."
    return error_msg
```

**--- NEW CODE ---**
```python
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

**📝 What Changed:**
- Added new `elif isinstance(core_exception, ValueError):` block
- Added pattern matching to detect specific error types
- Provides different user-friendly messages based on error pattern
- Keeps the existing `elif not fallback_to_error_msg:` block after the new block

---

## 📊 Complete Function Sections (For Reference)

### **File 1: `llm.py` - Complete `invoke_llm_json` Function End**

**Lines 190-215:**

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

### **File 2: `utils.py` - Complete `litellm_exception_to_error_msg` Function End**

**Lines 175-210:**

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

## ✅ Step-by-Step Implementation

### **Step 1: Modify `llm.py`**

1. Open: `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py`
2. Find: The `invoke_llm_json` function (around line 137)
3. Find: The empty response check (around line 197)
4. Replace: The `raise ValueError(...)` block with the NEW CODE from Change 1
5. Find: The JSON parsing try-except block (around line 203)
6. Replace: The `raise ValueError(...)` block with the NEW CODE from Change 2
7. Save the file

### **Step 2: Modify `utils.py`**

1. Open: `onyx-repo/backend/onyx/llm/utils.py`
2. Find: The `litellm_exception_to_error_msg` function (around line 80)
3. Find: The section with `elif isinstance(core_exception, APIError):` (around line 177)
4. Find: The line `elif not fallback_to_error_msg:` (around line 182)
5. **BEFORE** that line, add the NEW CODE from the ValueError handling block
6. Keep the existing `elif not fallback_to_error_msg:` block after the new code
7. Save the file

---

## 🧪 Testing

After making changes:

1. **Test with a prompt that previously failed:**
   - Send a complex question
   - If error occurs, check the message
   - Should see: "The AI system is taking longer than expected..."
   - Should NOT see: "Invalid JSON: EOF..."

2. **Test with normal prompts:**
   - Should work as before

---

## 📝 Summary

**Files to Change:**
1. ✅ `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py` (2 changes)
2. ✅ `onyx-repo/backend/onyx/llm/utils.py` (1 change)

**Total Changes:**
- 2 error messages replaced in `llm.py`
- 1 new error handling block added in `utils.py`

**Result:**
- ✅ Users see friendly messages instead of technical errors
- ✅ Clear guidance on what to do
- ✅ Better user experience

---

That's it! Follow the old/new code comparisons above to make the changes. 🎉


