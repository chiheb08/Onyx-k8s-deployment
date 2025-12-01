# Frontend Polling Optimization: Fix Endless Status Checks

## Problem: Endless Network Requests

**What you're seeing**: In the browser Network tab, you see endless calls to `/api/user/projects/file/statuses` every 3 seconds.

**Why it's a problem**:
- **Unnecessary load**: If a file takes 60 seconds to process, that's 20 requests
- **If it takes 120 seconds**: That's 40 requests!
- **Wastes bandwidth**: Each request is ~700 bytes, but adds up
- **Backend load**: Every request hits the database and API server

**Root cause**: Frontend polls every 3 seconds (`3000ms`) until files are completed.

---

## Solution: Optimize Polling Interval

### Current Code (Too Frequent)

```typescript
// File: web/src/app/chat/projects/ProjectsContext.tsx:666
pollIntervalRef.current = window.setInterval(poll, 3000); // Every 3 seconds!
```

### Recommended Fix: Increase Interval + Exponential Backoff

**Option 1: Simple Fix (5-10 seconds)**

```typescript
// Change line 666 from:
pollIntervalRef.current = window.setInterval(poll, 3000);

// To:
pollIntervalRef.current = window.setInterval(poll, 10000); // Every 10 seconds
```

**Impact**: Reduces requests by 66% (from 20 to 6 requests for 60s processing)

---

**Option 2: Exponential Backoff (Best Solution)**

This polls more frequently at first, then slows down over time:

```typescript
// Replace the polling logic (lines 663-667) with:

if (shouldPoll && pollIntervalRef.current === null) {
  let pollCount = 0;
  const maxInterval = 30000; // Max 30 seconds between polls
  const baseInterval = 5000;  // Start with 5 seconds
  
  const pollWithBackoff = async () => {
    await poll();
    pollCount++;
    
    // Exponential backoff: 5s, 10s, 15s, 20s, 25s, 30s, 30s...
    const currentInterval = Math.min(
      baseInterval * Math.ceil(pollCount / 2),
      maxInterval
    );
    
    // Clear old interval and set new one
    if (pollIntervalRef.current !== null) {
      window.clearInterval(pollIntervalRef.current);
    }
    
    // Only continue if there are still files being tracked
    if (trackedUploadIds.size > 0) {
      pollIntervalRef.current = window.setInterval(pollWithBackoff, currentInterval);
    }
  };
  
  // Start immediately, then use backoff
  pollWithBackoff();
  pollIntervalRef.current = window.setInterval(pollWithBackoff, baseInterval);
}
```

**Impact**: 
- First 10 seconds: Poll every 5s (2 requests)
- Next 20 seconds: Poll every 10s (2 requests)
- Next 30 seconds: Poll every 15s (2 requests)
- After that: Poll every 30s

**Total for 60s processing**: ~6 requests (vs 20 with current code)

---

## Exact Code Changes

### File: `web/src/app/chat/projects/ProjectsContext.tsx`

**Location**: Around line 663-667

**Current Code**:
```typescript
if (shouldPoll && pollIntervalRef.current === null) {
  // Kick once immediately, then start interval
  poll();
  pollIntervalRef.current = window.setInterval(poll, 3000);
}
```

**Recommended Change (Simple)**:
```typescript
if (shouldPoll && pollIntervalRef.current === null) {
  // Kick once immediately, then start interval
  poll();
  pollIntervalRef.current = window.setInterval(poll, 10000); // Changed from 3000 to 10000
}
```

**Recommended Change (Advanced with Backoff)**:
```typescript
if (shouldPoll && pollIntervalRef.current === null) {
  let pollCount = 0;
  const maxInterval = 30000; // Max 30 seconds
  const baseInterval = 5000;  // Start with 5 seconds
  
  const pollWithBackoff = async () => {
    await poll();
    pollCount++;
    
    // Exponential backoff: 5s → 10s → 15s → 20s → 25s → 30s
    const currentInterval = Math.min(
      baseInterval * Math.ceil(pollCount / 2),
      maxInterval
    );
    
    // Clear old interval
    if (pollIntervalRef.current !== null) {
      window.clearInterval(pollIntervalRef.current);
      pollIntervalRef.current = null;
    }
    
    // Continue polling if files still processing
    const ids = Array.from(trackedUploadIds);
    if (ids.length > 0) {
      pollIntervalRef.current = window.setInterval(pollWithBackoff, currentInterval);
    }
  };
  
  // Start immediately
  pollWithBackoff();
  pollIntervalRef.current = window.setInterval(pollWithBackoff, baseInterval);
}
```

---

## Comparison: Before vs After

### Before (Current - 3 seconds)

| Processing Time | Number of Requests | Total Data |
|----------------|-------------------|------------|
| 30 seconds | 10 requests | ~7 KB |
| 60 seconds | 20 requests | ~14 KB |
| 120 seconds | 40 requests | ~28 KB |

### After (Simple - 10 seconds)

| Processing Time | Number of Requests | Total Data | Reduction |
|----------------|-------------------|------------|-----------|
| 30 seconds | 3 requests | ~2 KB | 70% less |
| 60 seconds | 6 requests | ~4 KB | 70% less |
| 120 seconds | 12 requests | ~8 KB | 70% less |

### After (Advanced - Exponential Backoff)

| Processing Time | Number of Requests | Total Data | Reduction |
|----------------|-------------------|------------|-----------|
| 30 seconds | 4 requests | ~3 KB | 60% less |
| 60 seconds | 6 requests | ~4 KB | 70% less |
| 120 seconds | 8 requests | ~6 KB | 80% less |

---

## Implementation Steps

### Step 1: Choose Your Approach

- **Quick fix**: Change `3000` to `10000` (5 minutes)
- **Best solution**: Implement exponential backoff (15 minutes)

### Step 2: Make the Code Change

1. Open `onyx-repo/web/src/app/chat/projects/ProjectsContext.tsx`
2. Find line 666 (or search for `setInterval(poll, 3000)`)
3. Apply one of the changes above

### Step 3: Test

1. Upload a file
2. Open browser Network tab
3. Verify polling interval is now longer
4. Verify file still completes correctly

### Step 4: Deploy

```bash
# Build frontend
cd onyx-repo/web
npm run build

# Or if using Docker
docker build -t onyx-web:latest .
```

---

## Why This Works

### User Experience

- **No noticeable difference**: Users won't notice a 10-second vs 3-second update
- **Files still update**: Status still refreshes, just less frequently
- **Faster completion**: With backend optimizations, files complete faster anyway

### Backend Benefits

- **Less database load**: Fewer queries to check file status
- **Less API server load**: Fewer requests to process
- **Better scalability**: Can handle more concurrent users

### Network Benefits

- **Less bandwidth**: 70% fewer requests
- **Faster page load**: Less network activity = better performance
- **Better mobile experience**: Saves battery and data

---

## Additional Optimizations

### 1. Stop Polling When Tab is Hidden

```typescript
// Add this to the useEffect
useEffect(() => {
  const handleVisibilityChange = () => {
    if (document.hidden) {
      // Stop polling when tab is hidden
      if (pollIntervalRef.current !== null) {
        window.clearInterval(pollIntervalRef.current);
        pollIntervalRef.current = null;
      }
    } else if (trackedUploadIds.size > 0) {
      // Resume polling when tab is visible
      poll();
      pollIntervalRef.current = window.setInterval(poll, 10000);
    }
  };
  
  document.addEventListener('visibilitychange', handleVisibilityChange);
  
  return () => {
    document.removeEventListener('visibilitychange', handleVisibilityChange);
  };
}, [trackedUploadIds]);
```

### 2. Maximum Polling Duration

```typescript
// Stop polling after 5 minutes (files should be done by then)
const MAX_POLLING_DURATION = 5 * 60 * 1000; // 5 minutes
const startTime = Date.now();

const pollWithTimeout = async () => {
  if (Date.now() - startTime > MAX_POLLING_DURATION) {
    // Stop polling, assume files are stuck
    if (pollIntervalRef.current !== null) {
      window.clearInterval(pollIntervalRef.current);
      pollIntervalRef.current = null;
    }
    return;
  }
  await poll();
};
```

---

## Summary

### The Problem
- Frontend polls every 3 seconds
- Creates 20-40+ requests per file upload
- Unnecessary backend load

### The Solution
- **Simple**: Increase interval to 10 seconds (70% reduction)
- **Advanced**: Exponential backoff (70-80% reduction)

### Expected Results
- **Before**: 20 requests for 60s processing
- **After (Simple)**: 6 requests (70% less)
- **After (Advanced)**: 6 requests with smart backoff

### Implementation Time
- **Simple fix**: 5 minutes
- **Advanced fix**: 15 minutes

**Recommendation**: Start with the simple fix (10 seconds), then upgrade to exponential backoff if needed.

