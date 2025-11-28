# LLM "Repeating the Same Chunk" Error: Detailed Log Analysis

## Error Summary

```
ERROR: 11/28/2025 11:59:22 AM process_message.py 860: [API:1ILAQhq3] 
Failed to process chat message due to litellm.InternalServerError: 
The model is repeating the same chunk
```

**What it means**: The LLM (Language Model) got stuck in a loop, generating the same text repeatedly. The model server (vLLM) detected this and stopped the generation.

---

## Complete Log Breakdown

### 1. Pre-Error Logs (Normal Operation)

#### DEBUG: File Token Calculation
```
11:59:17 AM parse_user_files.py 105: [API:1ILAQhq3] 
Total file tokens: 2731, Available tokens: 99565, Allowed uploaded context tokens: 49782
```

**What's happening**:
- User attached files to their message
- Onyx calculated:
  - **Total file tokens**: 2,731 tokens (size of uploaded files)
  - **Available tokens**: 99,565 tokens (LLM's context window)
  - **Allowed uploaded context**: 49,782 tokens (50% of available)

**Technical explanation**:
- Onyx uses a "50% rule" for file context: Only use half the available tokens for files
- This leaves room for:
  - System prompts
  - Chat history
  - User's current message
  - LLM's response

**Code location**: `backend/onyx/chat/user_files/parse_user_files.py:105`

```python
# Simplified version of what's happening:
total_tokens = calculate_user_files_token_count(user_file_ids, db_session)
available_tokens = compute_max_document_tokens_for_persona(persona, user_input)
uploaded_context_cap = int(available_tokens * 0.5)  # 50% rule

logger.debug(
    f"Total file tokens: {total_tokens}, "
    f"Available tokens: {available_tokens}, "
    f"Allowed uploaded context tokens: {uploaded_context_cap}"
)
```

---

#### DEBUG: Tool Skipping
```
11:59:17 AM tool_constructor.py 227: [API:1ILAQhq3] 
Skipping tool WebSearchTool because it is not available
```

**What's happening**:
- Onyx tried to include the WebSearchTool (for internet search)
- But it's not configured/available
- Onyx skips it and continues

**Why this is OK**: Not all tools are required. Onyx works fine without web search.

---

#### INFO: Search Tool Initialization
```
11:59:17 AM search_tool.py 146: [API:1I1AQhq3] 
SearchTool: No Slack context provided
```

**What's happening**:
- Onyx is initializing the SearchTool (for internal document search)
- No Slack context is available (this is a regular web chat, not Slack)

**Why this is OK**: Slack context is optional. It's only used when Onyx is running in Slack.

---

#### INFO: Token Override
```
11:59:18 AM utils.py 555: [API:1ILAQhq3] 
Using override GEN_AI_MAX_TOKENS: 131072
```

**What's happening**:
- Onyx is using a custom token limit: 131,072 tokens
- This is likely configured via environment variable `GEN_AI_MAX_TOKENS`

**Technical explanation**:
- Default context windows vary by model:
  - GPT-4: 128K tokens
  - Claude 3: 200K tokens
  - Llama 3: 128K tokens
- This override sets a specific limit regardless of model

**Code location**: `backend/onyx/llm/utils.py:555`

---

#### INFO: Status Check Requests
```
11:59:20 AM h11_impl.py 473: [API:AQ3B9XbU] 
10.128.4.8:42412 - "POST /user/projects/file/statuses HTTP/1.1" 200

11:59:21 AM h11_impl.py 473: [API:-PYBKV2X] 
10.128.4.8:42414 - "POST /user/projects/file/statuses HTTP/1.1" 200
```

**What's happening**:
- Frontend is polling the API to check file upload status
- These are normal health checks
- Status 200 = Success

**Why this happens**: Frontend checks every few seconds to see if files are done processing.

---

### 2. The Error (The Problem)

#### ERROR: Model Repeating Chunk
```
11/28/2025 11:59:22 AM process_message.py 860: [API:1ILAQhq3] 
Failed to process chat message due to litellm.InternalServerError: 
The model is repeating the same chunk
```

**What's happening**:
- User sent a chat message
- Onyx processed it, retrieved documents, built the prompt
- Sent prompt to LLM (via vLLM)
- LLM started generating response
- **LLM got stuck repeating the same text**
- vLLM detected the repetition and stopped with an error

**Technical explanation**:

**What is "repeating the same chunk"?**

When an LLM generates text, it produces tokens one at a time:
```
Token 1: "The"
Token 2: " sales"
Token 3: " data"
Token 4: " shows"
Token 5: " that"
...
```

Sometimes, the LLM gets stuck:
```
Token 100: "October"
Token 101: " sales"
Token 102: " were"
Token 103: " $50,000"
Token 104: " October"  ← Repeating!
Token 105: " sales"   ← Repeating!
Token 106: " were"    ← Repeating!
Token 107: " $50,000" ← Repeating!
... (infinite loop)
```

**Why this happens**:

1. **Repetition Penalty Too Low**:
   - LLMs have a "repetition penalty" to prevent loops
   - If set too low, the model doesn't penalize repetition enough
   - Result: Model repeats the same phrase

2. **Model Server Bug (vLLM)**:
   - vLLM might have a bug in its repetition detection
   - Or the model itself has a bug

3. **Prompt Causes Loop**:
   - The prompt might contain repetitive patterns
   - Model learns the pattern and repeats it

4. **Context Window Issues**:
   - If context is too long, model might get confused
   - Starts repeating to "fill space"

5. **Model Temperature Too High**:
   - High temperature = more randomness
   - Can cause model to get stuck in loops

---

### 3. The Traceback (Call Stack)

```
Traceback (most recent call last):
  File "/app/onyx/chat/process_message.py", line 843, in stream_chat_message_objects
    yield from process_streamed_packets.process_streamed_packets(
  File "/app/onyx/chat/packet_proccessing/process_streamed_packets.py", line 20, in process_streamed_packets
    for packet in answer_processed_output:
  File "/app/onyx/chat/answer.py", line 150, in processed_streamed_output
    for packet in stream:
  File "/app/onyx/agents/agent_search/run_graph.py", line 81, in run_dr_graph
    yield from run_graph(compiled_graph, config, input)
  File "/app/onyx/agents/agent_search/run_graph.py", line 55, in run_graph
    for event in manage_sync_streaming(
  File "/app/onyx/agents/agent_search/run_graph.py", line 38, in manage_sync_streaming
    for event in compiled_graph.stream(
  File "/usr/local/lib/python3.11/site-packages/langgraph/pregel/__init__.py", line 1724, in stream
    for _ in runner.tick(
```

**What the traceback shows**:

This is the **call stack** - the path the code took to reach the error:

```
1. User sends message
   ↓
2. stream_chat_message_objects() - Main entry point
   ↓
3. process_streamed_packets() - Process LLM output packets
   ↓
4. answer.processed_streamed_output - Get answer from LLM
   ↓
5. run_dr_graph() - Run the agent graph (orchestrates LLM calls)
   ↓
6. compiled_graph.stream() - LangGraph streaming
   ↓
7. runner.tick() - LangGraph internal processing
   ↓
8. ERROR: LLM returns "repeating chunk" error
```

**Understanding the Stack**:

- **Top of stack** (line 843): Where the error was caught
- **Bottom of stack** (line 1724): Where the error originated (inside LangGraph)
- **Everything in between**: The chain of function calls

**Code Flow**:

```python
# File: backend/onyx/chat/process_message.py:843
def stream_chat_message_objects(...):
    try:
        # ... setup code ...
        
        # This is where the error happens
        yield from process_streamed_packets.process_streamed_packets(
            answer_processed_output=answer.processed_streamed_output,
        )
    except Exception as e:
        # Error is caught here (line 863)
        logger.exception(f"Failed to process chat message due to {e}")
        yield StreamingError(error=client_error_msg)
```

---

## What Happens After the Error

### Error Handling Flow

```python
# File: backend/onyx/chat/process_message.py:863-883

except Exception as e:
    # Step 1: Log the error
    logger.exception(f"Failed to process chat message due to {e}")
    
    # Step 2: Convert error to user-friendly message
    if llm:
        client_error_msg = litellm_exception_to_error_msg(e, llm)
        # This converts "InternalServerError: The model is repeating..." 
        # to a user-friendly message
    
    # Step 3: Send error to frontend
    yield StreamingError(error=client_error_msg, stack_trace=stack_trace)
    
    # Step 4: Rollback database transaction
    db_session.rollback()
    
    # Step 5: Stop processing
    return
```

**What the user sees**:
- Frontend receives `StreamingError` packet
- Error message is displayed to user
- Chat stops generating

---

## Root Causes and Solutions

### Cause 1: vLLM Configuration Issue

**Problem**: vLLM's repetition penalty is too low

**Solution**: Increase repetition penalty in vLLM config

```yaml
# vLLM configuration
generation_config:
  repetition_penalty: 1.2  # Increase from default (usually 1.0)
  # Higher = more penalty for repetition
```

**How to check**: Look at vLLM logs for repetition detection settings

---

### Cause 2: Model Temperature Too High

**Problem**: High temperature causes randomness, leading to loops

**Solution**: Lower temperature in Onyx persona settings

```python
# In persona configuration
temperature: 0.7  # Lower from 1.0 (default)
# Lower = more deterministic, less random
```

**Where to set**: Admin UI → Personas → Edit → Temperature

---

### Cause 3: Context Too Long

**Problem**: Very long context confuses the model

**Solution**: Reduce context size or chunk documents better

```python
# Environment variable
GEN_AI_MAX_TOKENS=65536  # Reduce from 131072
```

**Or**: Reduce number of document chunks fed to LLM

---

### Cause 4: vLLM Server Bug

**Problem**: vLLM has a bug in repetition detection

**Solution**: 
1. Update vLLM to latest version
2. Check vLLM GitHub issues
3. Report bug if reproducible

**How to check vLLM version**:
```bash
kubectl exec -it deployment/vllm-server -- python -c "import vllm; print(vllm.__version__)"
```

---

### Cause 5: Prompt Causes Loop

**Problem**: The prompt contains repetitive patterns

**Solution**: Review and improve prompt templates

**Where to check**: 
- `backend/onyx/prompts/` - Prompt templates
- Check if system prompts have repetitive instructions

---

## Immediate Actions

### 1. Check vLLM Logs

```bash
# Get vLLM server logs
kubectl logs -l app=vllm-server --tail=100 | grep -i "repeat"

# Look for:
# - Repetition detection messages
# - Model generation errors
# - Configuration warnings
```

### 2. Check Model Configuration

```bash
# Check what model is being used
kubectl exec -it deployment/api-server -- env | grep GEN_AI_MODEL

# Check token limits
kubectl exec -it deployment/api-server -- env | grep GEN_AI_MAX_TOKENS
```

### 3. Retry the Request

**For the user**: Simply try the same question again. This is often a transient issue.

**Why retries work**: 
- Model state is reset
- Different random seed
- Temporary vLLM issue might be resolved

---

## Prevention Strategies

### 1. Add Repetition Detection in Onyx

**Current**: Onyx relies on vLLM to detect repetition

**Improvement**: Add client-side repetition detection

```python
# Pseudo-code for improvement
def detect_repetition(text: str, window: int = 50) -> bool:
    """
    Check if last N tokens repeat.
    Returns True if repetition detected.
    """
    tokens = text.split()
    if len(tokens) < window * 2:
        return False
    
    last_window = tokens[-window:]
    previous_window = tokens[-window*2:-window]
    
    if last_window == previous_window:
        return True  # Repetition detected!
    return False
```

### 2. Add Retry Logic

**Current**: Error is shown to user, no retry

**Improvement**: Automatically retry with different parameters

```python
# Pseudo-code for improvement
def stream_chat_message_objects(...):
    max_retries = 3
    for attempt in range(max_retries):
        try:
            yield from process_streamed_packets(...)
            break  # Success!
        except InternalServerError as e:
            if "repeating" in str(e) and attempt < max_retries - 1:
                # Retry with lower temperature
                llm_model.temperature = max(0.1, llm_model.temperature - 0.2)
                continue
            raise  # Give up
```

### 3. Monitor and Alert

**Add monitoring** for repetition errors:

```python
# Track repetition error rate
if "repeating" in str(e):
    metrics.increment("llm.repetition_errors")
    
    # Alert if rate is high
    if metrics.get_rate("llm.repetition_errors") > 0.1:  # 10% error rate
        send_alert("High repetition error rate detected!")
```

---

## Understanding the Error Message

### Breaking Down "InternalServerError: The model is repeating the same chunk"

**InternalServerError**:
- Type of error from litellm
- Means: The LLM server (vLLM) returned a 500 error
- This is a server-side error, not a client-side error

**"The model is repeating the same chunk"**:
- Specific error message from vLLM
- vLLM detected that the model is generating the same tokens repeatedly
- vLLM stops generation to prevent infinite loops

**Why vLLM stops**:
- Infinite loops waste resources
- Generate meaningless output
- Cost money/time
- Better to fail fast than generate garbage

---

## Technical Deep Dive: How LLM Streaming Works

### Normal Streaming Flow

```
1. User sends message: "What were sales in October?"
   ↓
2. Onyx builds prompt:
   - System instructions
   - Chat history
   - Retrieved documents
   - User's question
   ↓
3. Send to vLLM (streaming mode)
   ↓
4. vLLM starts generating tokens:
   Token 1: "Based"
   Token 2: " on"
   Token 3: " the"
   Token 4: " sales"
   Token 5: " data"
   ...
   ↓
5. Each token is streamed back to Onyx
   ↓
6. Onyx forwards tokens to frontend
   ↓
7. Frontend displays tokens as they arrive
   ↓
8. Generation completes
   ↓
9. Final answer displayed
```

### What Happens When Repetition Occurs

```
1. Normal generation (tokens 1-100)
   ↓
2. Model starts repeating (tokens 101-150)
   "October sales were $50,000. October sales were $50,000. October..."
   ↓
3. vLLM detects repetition:
   - Compares recent tokens
   - Finds pattern: same 20 tokens repeated 3+ times
   - Stops generation
   ↓
4. vLLM returns error: "The model is repeating the same chunk"
   ↓
5. Onyx catches error
   ↓
6. Onyx sends error to frontend
   ↓
7. User sees error message
```

---

## Code Locations Reference

| Component | File | Line | Purpose |
|-----------|------|------|---------|
| Error caught | `chat/process_message.py` | 863 | Main error handler |
| Error converted | `llm/utils.py` | 80-184 | Convert to user message |
| Streaming | `chat/packet_proccessing/process_streamed_packets.py` | 20 | Process LLM output |
| LLM call | `llm/chat_llm.py` | 533-598 | Stream from LLM |
| Agent graph | `agents/agent_search/run_graph.py` | 38-81 | Orchestrate LLM calls |

---

## Summary

### What Happened

1. User sent a chat message with files attached
2. Onyx processed files, retrieved documents, built prompt
3. Sent prompt to vLLM for generation
4. vLLM started generating response
5. **vLLM detected model repeating same text**
6. vLLM stopped generation and returned error
7. Onyx caught error and displayed to user

### Why It Happened

- Most likely: vLLM configuration issue (repetition penalty too low)
- Or: Model temperature too high
- Or: vLLM server bug
- Or: Prompt causes loop

### What to Do

1. **Immediate**: User should retry (often transient)
2. **Short-term**: Check vLLM configuration, lower temperature
3. **Long-term**: Add client-side repetition detection, improve error handling

### Impact

- **User experience**: Request fails, user sees error
- **System**: No data corruption, just a failed request
- **Frequency**: Should be rare (<1% of requests)

---

## For Junior Engineers: Key Takeaways

1. **LLMs can get stuck**: They're not perfect, sometimes they loop
2. **Error handling is important**: Onyx catches the error gracefully
3. **Streaming is complex**: Many layers (Onyx → vLLM → Model → vLLM → Onyx → Frontend)
4. **Configuration matters**: Model settings (temperature, repetition penalty) affect behavior
5. **Retries help**: Transient issues often resolve on retry

**Remember**: This is a model/server issue, not an Onyx bug. Onyx is correctly detecting and handling the error!

