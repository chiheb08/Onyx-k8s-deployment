# Step-by-Step Fix: Orchestrator JSON Error (User-Friendly)

## 🎯 What We're Fixing

**Error Users See:**
```
Invalid JSON: EOF while parsing a value at line 1 column 0
```

**What This Means:**
The AI system couldn't process your request because it received an incomplete response. This is usually a temporary issue.

---

## ✅ Solution Overview

We'll improve the error handling to:
1. Show a user-friendly message instead of technical errors
2. Provide helpful guidance on what to do
3. Make it easier to understand what went wrong

---

## 📝 Step-by-Step Implementation

### **Step 1: Improve Error Message in Backend**

**File:** `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py`

**Location:** `invoke_llm_json` function (around line 197-210)

**✏️ WHAT TO CHANGE:**

**--- OLD ---**
```python
    # Validate that we have content before parsing
    if not response_content or not response_content.strip():
        logger.error(
            f"LLM returned empty or invalid JSON response. "
            f"Model: {llm.config.model_name}, Provider: {llm.config.model_provider}. "
            f"This usually means the LLM timed out, was interrupted, or failed to generate a response."
        )
        raise ValueError(
            f"LLM returned empty response when JSON was expected. "
            f"This usually means the LLM timed out, was interrupted, or failed to generate a response. "
            f"Please try again or check your LLM configuration."
        )
```

**--- NEW ---**
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
```

**--- OLD ---**
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

**--- NEW ---**
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

---

### **Step 2: Add Error Mapping for Better Messages**

**File:** `onyx-repo/backend/onyx/llm/utils.py`

**Location:** `litellm_exception_to_error_msg` function (around line 80-185)

**Purpose:** This function converts technical errors to user-friendly messages.

**✏️ WHAT TO ADD:**

Find the section where it handles `ValueError` or add a new check. Look for the end of the function (around line 182-184):

**--- OLD ---**
```python
    elif not fallback_to_error_msg:
        error_msg = "An unexpected error occurred while processing your request. Please try again later."
    return error_msg
```

**--- NEW ---**
```python
    elif isinstance(core_exception, ValueError):
        # Check for specific error patterns and provide user-friendly messages
        error_str = str(core_exception).lower()
        
        if "empty response" in error_str or "invalid json" in error_str or "eof" in error_str:
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
        elif "failed to parse" in error_str:
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

## 🎨 User-Friendly Error Messages

### **What Users Will See Instead:**

**Before (Technical):**
```
Invalid JSON: EOF while parsing a value at line 1 column 0
```

**After (User-Friendly):**
```
The AI system is taking longer than expected to process your request. 
This usually happens when the system is busy or your request is very complex. 
Please wait a moment and try again. If the problem continues, try simplifying your question.
```

---

## ✅ Complete Code Changes

### **File 1: `llm.py`**

**Location:** Lines 190-210

**Complete section after changes:**

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

### **File 2: `utils.py`**

**Location:** Lines 182-185 (end of `litellm_exception_to_error_msg` function)

**Complete section after changes:**

```python
    elif isinstance(core_exception, ValueError):
        # Check for specific error patterns and provide user-friendly messages
        error_str = str(core_exception).lower()
        
        if "empty response" in error_str or "invalid json" in error_str or "eof" in error_str:
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
        elif "failed to parse" in error_str:
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

After making changes:

- [ ] ✅ Error messages in `llm.py` are user-friendly
- [ ] ✅ Error mapping added in `utils.py`
- [ ] ✅ Code indentation is correct
- [ ] ✅ No syntax errors

---

## 🧪 Testing

After implementing:

1. **Test with a prompt that previously failed:**
   - **Expected:** User-friendly error message instead of technical error
   - **Message should:** Explain what happened and what to do

2. **Test with normal prompts:**
   - **Expected:** Works as before (no changes to normal flow)

3. **Check error display:**
   - **Expected:** Error appears in UI with clear, helpful message

---

## 📊 Summary

**What We Changed:**
1. ✅ Replaced technical error messages with user-friendly ones
2. ✅ Added error pattern matching for better messages
3. ✅ Provided clear guidance on what users should do

**Result:**
- ✅ Users see helpful messages instead of technical errors
- ✅ Clear guidance on what to do next
- ✅ Better user experience

**Files Modified:**
- `onyx-repo/backend/onyx/agents/agent_search/shared_graph_utils/llm.py`
- `onyx-repo/backend/onyx/llm/utils.py`

---

## 💬 Example Error Messages

### **Scenario 1: Empty Response**

**User sees:**
> "The AI system is taking longer than expected to process your request. This usually happens when the system is busy or your request is very complex. Please wait a moment and try again. If the problem continues, try simplifying your question or contact support."

### **Scenario 2: JSON Parsing Error**

**User sees:**
> "The AI system encountered an issue processing your request. This can happen when the system is busy or your request is very complex. Please try again in a moment. If the problem continues, try rephrasing your question or contact support."

### **Scenario 3: Timeout**

**User sees:**
> "Your request took too long to process. This can happen with complex questions or when the system is busy. Please try again or simplify your question."

---

That's it! Follow these steps and users will see helpful messages instead of technical errors. 🎉


