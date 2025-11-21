# User Information in Prompts - Issue and Solutions

## 🔍 Problem Description

Onyx automatically adds user information (name, role, email) to the system prompt sent to the LLM. This can cause the model to incorrectly associate the user's personal information with the content being discussed.

**Example Issue:**
- User asks: "How should I communicate with a taxpayer?"
- System prompt includes: "User's email: john.doe@company.com"
- LLM might incorrectly add the user's email to the response, thinking it's part of the taxpayer communication example

**GitHub Issue:** [Reference to the issue where this was reported]

---

## 📍 Where It Happens

The user information is added through the following code flow:

### 1. **Memory Callback Creation** (`backend/onyx/chat/memories.py`)

```python
def make_memories_callback(
    user: User | None, db_session: Session
) -> Callable[[], list[str]]:
    def memories_callback() -> list[str]:
        if user is None:
            return []

        user_info = [
            f"User's name: {user.personal_name}" if user.personal_name else "",
            f"User's role: {user.personal_role}" if user.personal_role else "",
            f"User's email: {user.email}" if user.email else "",  # ← Problem here
        ]

        memory_rows = db_session.scalars(
            select(Memory).where(Memory.user_id == user.id)
        ).all()
        memories = [memory.memory_text for memory in memory_rows if memory.memory_text]
        return user_info + memories  # ← User info is included

    return memories_callback
```

**Lines 17-21:** User information (name, role, email) is automatically collected and added to the memories list.

### 2. **Memory Handling** (`backend/onyx/prompts/prompt_utils.py`)

```python
def handle_memories(prompt_str: str, memories_callback: Callable[[], list[str]]) -> str:
    memories = memories_callback()
    if not memories:
        return prompt_str
    memories_str = "\n".join(memories)
    prompt_str += f"Information about the user asking the question:\n{memories_str}\n"  # ← Added to system prompt
    return prompt_str
```

**Lines 116-122:** The memories (including user info) are appended to the system prompt with the prefix "Information about the user asking the question:".

### 3. **System Message Building** (`backend/onyx/chat/prompt_builder/answer_prompt_builder.py`)

```python
def default_build_system_message(
    prompt_config: PromptConfig,
    llm_config: LLMConfig,
    memories_callback: Callable[[], list[str]] | None = None,
) -> SystemMessage | None:
    # ... system prompt building ...
    
    if memories_callback:
        tag_handled_prompt = handle_memories(tag_handled_prompt, memories_callback)  # ← Called here
    
    return SystemMessage(content=tag_handled_prompt)
```

**Lines 139-140:** The `handle_memories` function is called during system message construction, adding user information to the prompt.

### 4. **Usage in Chat Processing** (`backend/onyx/chat/process_message.py`)

```python
mem_callback = make_memories_callback(user, db_session)  # ← Created here
system_message = (
    default_build_system_message_for_default_assistant_v2(
        prompt_config=prompt_config,
        llm_config=llm_config,
        memories_callback=mem_callback,  # ← Passed to system message builder
        # ...
    )
)
```

**Line 774:** The memories callback is created and passed to the system message builder.

---

## ⚠️ Why This Is Problematic

1. **Context Confusion**: When discussing topics like "communication with a taxpayer," the LLM might incorrectly use the user's email/name as an example, thinking it's part of the requested content.

2. **Privacy Concerns**: User email addresses and names are sent to the LLM in every request, which may not be desired in all deployment scenarios.

3. **Unintended Behavior**: The user information is added automatically without explicit user consent or configuration, making it hard to control.

4. **Token Waste**: Including user information in every prompt consumes tokens unnecessarily if the information isn't needed for the task.

---

## ✅ Solutions

### Solution 1: Remove Email/Username from User Info (Recommended)

**Modify:** `backend/onyx/chat/memories.py`

**Change:**
```python
# --- OLD ---
user_info = [
    f"User's name: {user.personal_name}" if user.personal_name else "",
    f"User's role: {user.personal_role}" if user.personal_role else "",
    f"User's email: {user.email}" if user.email else "",
]

# --- NEW ---
# Only include role if needed, exclude email and name to prevent confusion
user_info = [
    f"User's role: {user.personal_role}" if user.personal_role else "",
    # Removed: name and email to prevent LLM from incorrectly using them in responses
]
```

**Impact:**
- ✅ Removes email and name from prompts
- ✅ Keeps role information (if needed for context)
- ✅ Maintains memory functionality for other user memories
- ⚠️ Requires code modification and redeployment

---

### Solution 2: Add Environment Variable to Control User Info Inclusion

**Step 1: Add Config Variable** (`backend/onyx/configs/app_configs.py`)

Add this in the "User Facing Features Configs" section (around line 37):

```python
# Controls whether user information (name, email, role) is included in prompts
# Set to "false" to prevent user info from being added to LLM prompts
INCLUDE_USER_INFO_IN_PROMPT = (
    os.environ.get("INCLUDE_USER_INFO_IN_PROMPT", "true").lower() == "true"
)
```

**Step 2: Modify Memory Callback** (`backend/onyx/chat/memories.py`)

```python
from onyx.configs.app_configs import INCLUDE_USER_INFO_IN_PROMPT

def make_memories_callback(
    user: User | None, db_session: Session
) -> Callable[[], list[str]]:
    def memories_callback() -> list[str]:
        if user is None:
            return []

        user_info = []
        if INCLUDE_USER_INFO_IN_PROMPT:
            user_info = [
                f"User's name: {user.personal_name}" if user.personal_name else "",
                f"User's role: {user.personal_role}" if user.personal_role else "",
                f"User's email: {user.email}" if user.email else "",
            ]

        memory_rows = db_session.scalars(
            select(Memory).where(Memory.user_id == user.id)
        ).all()
        memories = [memory.memory_text for memory in memory_rows if memory.memory_text]
        return user_info + memories

    return memories_callback
```

**Step 3: Update Kubernetes ConfigMap**

In your `05-configmap.yaml` or equivalent:

```yaml
data:
  # ... other configs ...
  INCLUDE_USER_INFO_IN_PROMPT: "false"  # Set to "false" to disable user info in prompts
```

**Impact:**
- ✅ Configurable via environment variable
- ✅ No code changes needed after initial implementation
- ✅ Can be toggled per deployment
- ⚠️ Requires code modification and redeployment

---

### Solution 3: Exclude Only Email (Selective Removal)

**Modify:** `backend/onyx/chat/memories.py`

```python
# --- OLD ---
user_info = [
    f"User's name: {user.personal_name}" if user.personal_name else "",
    f"User's role: {user.personal_role}" if user.personal_role else "",
    f"User's email: {user.email}" if user.email else "",
]

# --- NEW ---
# Exclude email to prevent LLM from incorrectly using it in responses
user_info = [
    f"User's name: {user.personal_name}" if user.personal_name else "",
    f"User's role: {user.personal_role}" if user.personal_role else "",
    # Email removed: prevents confusion when discussing communication examples
]
```

**Impact:**
- ✅ Removes only email (most problematic field)
- ✅ Keeps name and role for context
- ✅ Minimal change
- ⚠️ Still includes name, which might cause issues in some scenarios

---

## 🎯 Recommended Approach

**For Immediate Fix:** Use **Solution 1** (Remove Email/Username) - it's the simplest and most direct fix.

**For Long-term Flexibility:** Implement **Solution 2** (Environment Variable) - allows you to control the behavior without code changes.

**For Minimal Impact:** Use **Solution 3** (Exclude Only Email) - if you still want name/role context but want to avoid email confusion.

---

## 📋 Implementation Checklist

### If Using Solution 1 (Remove Email/Username):

1. [ ] Modify `backend/onyx/chat/memories.py` to remove email and name from `user_info`
2. [ ] Test locally to ensure prompts no longer include user email/name
3. [ ] Build new Docker image
4. [ ] Deploy to staging environment
5. [ ] Verify prompts in logs don't contain user email/name
6. [ ] Deploy to production

### If Using Solution 2 (Environment Variable):

1. [ ] Add `INCLUDE_USER_INFO_IN_PROMPT` to `backend/onyx/configs/app_configs.py`
2. [ ] Modify `backend/onyx/chat/memories.py` to check the config variable
3. [ ] Update Kubernetes ConfigMap with `INCLUDE_USER_INFO_IN_PROMPT: "false"`
4. [ ] Test locally with the environment variable set
5. [ ] Build new Docker image
6. [ ] Deploy to staging environment
7. [ ] Verify prompts in logs don't contain user info when disabled
8. [ ] Deploy to production

---

## 🔍 How to Verify the Fix

### Check System Prompts in Logs

1. **Enable Logging:**
   ```yaml
   # In ConfigMap
   LOG_ONYX_MODEL_INTERACTIONS: "true"
   ```

2. **Check API Server Logs:**
   ```bash
   kubectl logs -f deployment/api-server | grep -i "system"
   ```

3. **Look for User Info:**
   - ❌ **Before Fix:** You'll see lines like:
     ```
     Information about the user asking the question:
     User's email: john.doe@company.com
     User's name: John Doe
     ```
   - ✅ **After Fix:** User email/name should not appear in system prompts

### Test with a Sample Query

1. Ask: "How should I communicate with a taxpayer?"
2. Check the LLM response
3. **Before Fix:** Response might incorrectly include your email
4. **After Fix:** Response should not include your email

---

## 📝 Additional Notes

- **User Memories:** The fix only affects automatic user info (name, role, email). Custom user memories stored in the `Memory` table will still be included if they exist.

- **Backward Compatibility:** Removing user info from prompts should not break existing functionality, as the LLM doesn't strictly require this information to function.

- **Role Information:** If you keep role information, it can still be useful for context-aware responses (e.g., "as a tax advisor, you should..."), but be aware it might still cause confusion in some scenarios.

---

## 🔗 Related Files

- `backend/onyx/chat/memories.py` - Memory callback creation
- `backend/onyx/prompts/prompt_utils.py` - Memory handling in prompts
- `backend/onyx/chat/prompt_builder/answer_prompt_builder.py` - System message building
- `backend/onyx/chat/process_message.py` - Chat message processing
- `backend/onyx/configs/app_configs.py` - Configuration variables

---

## 📚 References

- GitHub Issue: [Link to the issue where this was reported]
- Onyx Documentation: [Link to relevant docs if available]

