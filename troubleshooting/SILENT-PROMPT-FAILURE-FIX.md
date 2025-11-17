# Silent Prompt Failures - Troubleshooting & Fix

This document explains why prompts sometimes fail silently (loading indicator disappears without error) and provides step-by-step solutions.

---

## The Problem

**Symptoms:**
- User sends a prompt
- Loading indicator (white dot) appears
- Loading indicator disappears without any error message
- No response is generated
- No warning or error is shown to the user

**This is a silent failure** - the error occurs but is never displayed to the user.

---

## Root Cause Analysis

### How Streaming Works

```
┌─────────────────────────────────────────────────────────┐
│              USER SENDS PROMPT                           │
│  "What is the vacation policy?"                          │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
        ┌───────────────────────────────┐
        │   FRONTEND: sendMessage()      │
        │  (Creates fetch request)      │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   BACKEND: /api/chat/send-    │
        │   message (StreamingResponse)  │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   STREAMING (SSE)             │
        │  - Packets streamed one by one│
        │  - Frontend processes packets │
        │  - Updates UI in real-time    │
        └──────────┬────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
        ▼                     ▼
   SUCCESS              FAILURE
   (Packets arrive)     (Stream breaks)
```

### The Bug: Error Not Checked

**What happens when stream fails:**

1. **Stream starts** → Loading indicator appears
2. **Stream fails** (network error, timeout, backend crash, etc.)
3. **Error is caught** in `updateCurrentMessageFIFO()` → Stored in `stack.error`
4. **`stack.isComplete = true`** is set
5. **Loop exits** because `stack.isComplete` is true and `stack.isEmpty()` is true
6. **`stack.error` is NEVER checked!** ❌
7. **Chat state resets to "input"** → Loading indicator disappears
8. **No error message shown** → User sees nothing

**Code location:** `web/src/app/chat/hooks/useChatController.ts` (line ~727)

```typescript
// Current code (BUGGY):
while (!stack.isComplete || !stack.isEmpty()) {
  // Process packets...
}

// After loop exits, stack.error is never checked!
// If stream failed before any packets, error is lost
```

---

## Why This Happens

### Common Failure Scenarios

#### Scenario 1: Network Timeout

```
1. User sends prompt
2. Request sent to backend
3. Backend starts processing
4. Network connection drops (timeout, proxy issue, etc.)
5. Stream reader throws error: "Unable to process chunk"
6. Error stored in stack.error
7. Loop exits, error never displayed
```

#### Scenario 2: Backend Crash

```
1. User sends prompt
2. Backend receives request
3. Backend starts streaming
4. Backend crashes (OOM, exception, etc.)
5. Stream closes abruptly
6. Frontend detects stream end
7. Error stored in stack.error
8. Loop exits, error never displayed
```

#### Scenario 3: NGINX/Proxy Timeout

```
1. User sends prompt
2. Request goes through NGINX
3. NGINX timeout expires (default 60s)
4. NGINX closes connection
5. Frontend sees stream end
6. Error stored in stack.error
7. Loop exits, error never displayed
```

#### Scenario 4: LLM Provider Error

```
1. User sends prompt
2. Backend calls LLM (vLLM/OpenAI/etc.)
3. LLM provider returns error
4. Backend should send StreamingError packet
5. But if connection breaks before packet sent...
6. Frontend sees stream end
7. Error stored in stack.error
8. Loop exits, error never displayed
```

---

## Step-by-Step Troubleshooting

### Step 1: Check Browser Console

**Open browser DevTools (F12) and check Console tab:**

```javascript
// Look for errors like:
"Error parsing SSE data: ..."
"Unable to process chunk"
"Failed to fetch"
"NetworkError"
"AbortError"
```

**What to look for:**
- Network errors
- JSON parsing errors
- Stream read errors

### Step 2: Check Network Tab

**In DevTools → Network tab:**

1. **Filter by "send-message"** or "chat"
2. **Find the failed request**
3. **Check:**
   - Status code (200, 500, timeout?)
   - Response headers
   - Response body (if any)
   - Timing (did it timeout?)

**Common issues:**
- Status 200 but no response body → Stream closed early
- Status 500 → Backend error
- Status 504 → Gateway timeout
- Pending forever → Request stuck

### Step 3: Check Backend Logs

**Check API server logs:**

```bash
# In Kubernetes/OpenShift
kubectl logs -f deployment/api-server -n <namespace> | grep -i "error\|exception\|stream"

# Look for:
"Error in chat message streaming"
"Failed to process chat message"
"Stream generator finished"
```

**What to look for:**
- Exceptions during streaming
- LLM provider errors
- Database connection errors
- Timeout errors

### Step 4: Check NGINX Logs

**If using NGINX:**

```bash
kubectl logs -f deployment/nginx -n <namespace>

# Look for:
- 504 Gateway Timeout
- Connection reset
- Upstream timeout
```

### Step 5: Check LLM Provider

**If using external LLM (OpenAI, Anthropic, etc.):**

- Check provider status page
- Check API key validity
- Check rate limits
- Check quota/billing

---

## Solutions

### Solution 1: Fix Frontend Error Handling (Recommended)

**Problem:** `stack.error` is never checked after the loop exits.

**Fix:** Check for errors after the packet processing loop.

**File:** `web/src/app/chat/hooks/useChatController.ts`

**Location:** After the `while (!stack.isComplete || !stack.isEmpty())` loop (around line 859, right before the `} catch (e: any) {` block)

**Current code (BUGGY):**
```typescript
            currentMessageTreeLocal = newMessageDetails.messageTree;
          }
        }
      } catch (e: any) {
        console.log("Error:", e);
        // ... error handling
      }
```

**Fixed code:**
```typescript
            currentMessageTreeLocal = newMessageDetails.messageTree;
          }
        }
        
        // ✅ ADD THIS: Check for stream errors after loop exits
        if (stack.error) {
          setUncaughtError(frozenSessionId, stack.error);
          updateChatStateAction(frozenSessionId, "input");
          updateSubmittedMessage(getCurrentSessionId(), "");
          
          // Show error to user
          setPopup({
            type: "error",
            message: `Request failed: ${stack.error}. Please check your connection and try again.`,
          });
          
          // Don't continue with message creation
          resetRegenerationState(frozenSessionId);
          return;
        }
      } catch (e: any) {
        console.log("Error:", e);
        // ... existing error handling
      }
```

**Why this works:**
- Catches errors that occur before any packets arrive
- Displays error message to user
- Prevents silent failures

---

### Solution 2: Improve Stream Error Detection

**Problem:** Some errors might not be caught properly in `handleSSEStream`.

**Fix:** Add better error handling in the stream reader.

**File:** `web/src/lib/search/streamingUtils.ts`

**Location:** `handleSSEStream` function (around line 81)

**Current code:**
```typescript
while (true) {
  const rawChunk = await reader?.read();
  if (!rawChunk) {
    throw new Error("Unable to process chunk");
  }
  // ...
}
```

**Improved code:**
```typescript
while (true) {
  try {
    const rawChunk = await reader?.read();
    if (!rawChunk) {
      throw new Error("Stream ended unexpectedly - no data received");
    }
    // ... rest of processing
  } catch (error) {
    // Log the error for debugging
    console.error("Stream read error:", error);
    
    // Re-throw with more context
    if (error instanceof Error) {
      throw new Error(`Stream failed: ${error.message}`);
    }
    throw error;
  }
}
```

---

### Solution 3: Add Timeout Detection

**Problem:** Long-running requests might timeout without clear error.

**Fix:** Add timeout detection in the fetch request.

**File:** `web/src/app/chat/services/lib.tsx`

**Location:** `sendMessage` function (around line 251)

**Current code:**
```typescript
const response = await fetch(`/api/chat/send-message`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
  },
  body,
  signal,
});
```

**Improved code:**
```typescript
// Add timeout
const timeoutId = setTimeout(() => {
  if (signal && !signal.aborted) {
    controller.abort(); // Abort the request
  }
}, 300000); // 5 minutes timeout

try {
  const response = await fetch(`/api/chat/send-message`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body,
    signal,
  });
  
  clearTimeout(timeoutId);
  
  if (!response.ok) {
    const errorText = await response.text().catch(() => "Unknown error");
    throw new Error(`HTTP ${response.status}: ${errorText}`);
  }
  
  yield* handleSSEStream<PacketType>(response, signal);
} catch (error) {
  clearTimeout(timeoutId);
  if (error instanceof Error && error.name === "AbortError") {
    throw new Error("Request timed out. Please try again.");
  }
  throw error;
}
```

---

### Solution 4: Improve Backend Error Reporting

**Problem:** Backend might not send error packets properly.

**Fix:** Ensure all errors are sent as `StreamingError` packets.

**File:** `backend/onyx/server/query_and_chat/chat_backend.py`

**Location:** `stream_generator` function (around line 469)

**Current code:**
```python
def stream_generator() -> Generator[str, None, None]:
    try:
        for packet in stream_chat_message(...):
            yield packet
    except Exception as e:
        logger.exception("Error in chat message streaming")
        yield json.dumps({"error": str(e)})
```

**Improved code:**
```python
def stream_generator() -> Generator[str, None, None]:
    try:
        for packet in stream_chat_message(...):
            yield packet
    except Exception as e:
        logger.exception("Error in chat message streaming")
        # Ensure error is properly formatted as StreamingError
        error_packet = {
            "error": str(e),
            "stack_trace": traceback.format_exc() if logger.level <= logging.DEBUG else None
        }
        yield json.dumps(error_packet)
    finally:
        logger.debug("Stream generator finished")
```

---

### Solution 5: Add Connection Health Check

**Problem:** Connection might be silently dropped.

**Fix:** Add periodic health checks during streaming.

**File:** `web/src/app/chat/services/currentMessageFIFO.ts`

**Location:** `updateCurrentMessageFIFO` function

**Add connection monitoring:**
```typescript
export async function updateCurrentMessageFIFO(
  stack: CurrentMessageFIFO,
  params: SendMessageParams
) {
  let lastPacketTime = Date.now();
  const HEALTH_CHECK_INTERVAL = 30000; // 30 seconds
  
  const healthCheck = setInterval(() => {
    const timeSinceLastPacket = Date.now() - lastPacketTime;
    if (timeSinceLastPacket > HEALTH_CHECK_INTERVAL && !stack.isComplete) {
      console.warn("Stream appears stalled - no packets received");
      // Could trigger a timeout error here
    }
  }, HEALTH_CHECK_INTERVAL);
  
  try {
    for await (const packet of sendMessage(params)) {
      lastPacketTime = Date.now();
      if (params.signal?.aborted) {
        throw new Error("AbortError");
      }
      stack.push(packet);
    }
  } catch (error: unknown) {
    clearInterval(healthCheck);
    if (error instanceof Error) {
      if (error.name === "AbortError") {
        console.debug("Stream aborted");
      } else {
        stack.error = error.message;
      }
    } else {
      stack.error = String(error);
    }
  } finally {
    clearInterval(healthCheck);
    stack.isComplete = true;
  }
}
```

---

## Quick Fix (Immediate Solution)

**The fastest fix is to check `stack.error` after the loop:**

**File:** `web/src/app/chat/hooks/useChatController.ts`

**Find this section (around line 859, after the while loop, before the catch block):**
```typescript
            currentMessageTreeLocal = newMessageDetails.messageTree;
          }
        }
      } catch (e: any) {
        console.log("Error:", e);
        const errorMsg = e.message;
        // ... error handling
      }
```

**Add this RIGHT BEFORE the `} catch (e: any) {` line:**
```typescript
            currentMessageTreeLocal = newMessageDetails.messageTree;
          }
        }
        
        // ✅ ADD THIS: Check for stream errors after loop exits
        if (stack.error) {
          setUncaughtError(frozenSessionId, stack.error);
          updateChatStateAction(frozenSessionId, "input");
          updateSubmittedMessage(getCurrentSessionId(), "");
          setPopup({
            type: "error",
            message: `Request failed: ${stack.error}. Please check your connection and try again.`,
          });
          resetRegenerationState(frozenSessionId);
          return;
        }
      } catch (e: any) {
        console.log("Error:", e);
        const errorMsg = e.message;
        // ... existing error handling
      }
```

**Important:** Make sure this code is inside the `try` block, right before the `catch` block. The error check should happen after the while loop completes but before any exceptions are caught.

---

## Prevention

### Best Practices

1. **Always check `stack.error`** after stream processing
2. **Add timeout handling** for long-running requests
3. **Log all stream errors** for debugging
4. **Show user-friendly error messages**
5. **Add retry logic** for transient failures
6. **Monitor stream health** during processing

### Monitoring

**Set up alerts for:**
- High rate of failed streams
- Long stream durations
- Network timeouts
- Backend errors during streaming

---

## Testing the Fix

### Test Case 1: Network Disconnect

1. Start a prompt
2. Disconnect network (turn off WiFi)
3. **Expected:** Error message appears: "Request failed: Network error..."
4. **Before fix:** Loading indicator disappears, no error

### Test Case 2: Backend Timeout

1. Send a prompt that takes longer than timeout
2. **Expected:** Error message: "Request timed out..."
3. **Before fix:** Loading indicator disappears, no error

### Test Case 3: Invalid Request

1. Send a prompt with invalid parameters
2. **Expected:** Error message with details
3. **Before fix:** Loading indicator disappears, no error

---

## Summary

**The Problem:**
- Stream fails before any packets arrive
- Error stored in `stack.error` but never checked
- Loading indicator disappears
- No error shown to user

**The Fix:**
- Check `stack.error` after packet processing loop
- Display error message to user
- Set chat state back to "input" properly

**Files to Modify:**
1. `web/src/app/chat/hooks/useChatController.ts` - Add error check after loop
2. `web/src/lib/search/streamingUtils.ts` - Improve error handling (optional)
3. `web/src/app/chat/services/lib.tsx` - Add timeout handling (optional)

**Priority:**
- **High:** Fix error checking in `useChatController.ts` (Solution 1)
- **Medium:** Improve stream error detection (Solution 2)
- **Low:** Add timeout and health checks (Solutions 3-5)

---

This fix will ensure that users always see an error message when prompts fail, instead of experiencing silent failures.

