# Official Onyx Repository - Issue Check Results

## 🔍 Search Results Summary

**Date Checked:** December 2025

**Repository:** `onyx-dot-app/onyx` (Official Onyx GitHub repository)

---

## ❌ **No Specific Issue Found**

**Finding:** There is **no existing issue** in the official Onyx repository that specifically addresses the problem where:
- Internal documents don't appear in the documents section on the **first prompt**
- But the same documents **do appear** on the **second prompt**

---

## 🔗 **Related Issue Found**

### **Issue #6493: "Re-Index not working with documents created via ingestion API"**

**Status:** ✅ **OPEN** (as of December 1, 2025)

**Description:** 
- Documents created via ingestion API are not immediately searchable
- Related to re-indexing functionality
- May be related to Vespa eventual consistency issues

**Relevance:**
- ⚠️ **Partially related** - Both involve documents not being immediately searchable
- ⚠️ **Different scope** - This issue is about re-indexing, not first prompt behavior
- ⚠️ **Different cause** - This is about ingestion API, not user file uploads

**Link:** https://github.com/onyx-dot-app/onyx/issues/6493

---

## 📊 **What This Means**

### **For Your Issue:**

1. ✅ **Not reported yet** - This specific problem hasn't been reported to the official repo
2. ✅ **Unique issue** - Your finding is valuable and should be reported
3. ✅ **Solution needed** - The fix we implemented is likely the first solution for this problem

### **Why It's Not Reported:**

- This is a **subtle UX issue** that might not be noticed by all users
- Users might assume it's normal behavior (waiting for second prompt)
- It requires specific conditions (large files, immediate prompt after upload)
- It's not a "breaking" bug, just a UX inconsistency

---

## 💡 **Recommendation**

### **Option 1: Report the Issue** (Recommended)

**Benefits:**
- ✅ Helps the Onyx team understand the problem
- ✅ May lead to an official fix
- ✅ Helps other users experiencing the same issue
- ✅ Can reference our solution as a potential fix

**How to Report:**

1. Go to: https://github.com/onyx-dot-app/onyx/issues/new
2. Title: "Documents don't appear in search results on first prompt after upload"
3. Description should include:
   - **Problem:** Documents uploaded via UI don't appear in documents section on first prompt, but appear on second prompt
   - **Root Cause:** Vespa eventual consistency - chunks written but not immediately searchable
   - **Steps to Reproduce:**
     1. Upload a large file (e.g., 50+ page PDF)
     2. Immediately send a prompt referencing the file
     3. Observe: File doesn't appear in documents section
     4. Send second prompt
     5. Observe: File appears in documents section
   - **Expected Behavior:** File should appear in documents section on first prompt
   - **Environment:** OpenShift/Kubernetes deployment, Vespa backend
   - **Potential Solution:** Add delay before marking file as COMPLETED, or retry logic in search

### **Option 2: Keep Our Solution Private**

**Benefits:**
- ✅ You have a working solution
- ✅ No need to coordinate with upstream
- ✅ Can customize as needed

**Drawbacks:**
- ⚠️ Others may experience the same issue
- ⚠️ May conflict with future official fixes
- ⚠️ Miss opportunity to contribute to Onyx

---

## 🔧 **Our Solution Status**

### **What We've Implemented:**

1. ✅ **Layer 2 (Retry Logic)** - Already implemented in `dr_basic_search_2_act.py`
   - Retries search after 1 second if no results found
   - Provides safety net for eventual consistency

2. ⏭️ **Layer 1 (Smart Delay)** - Documented but not yet implemented
   - Prevents issue at source by delaying COMPLETED status
   - Adapts delay based on chunk count

3. ⏭️ **Layer 3 (Env Var Control)** - Documented as optional
   - Makes delay configurable via environment variables

### **Next Steps:**

1. **Implement Layer 1** (Smart Delay) - Recommended
2. **Test thoroughly** with various file sizes
3. **Consider reporting** to official repo (optional but recommended)
4. **Monitor** for any conflicts with future Onyx updates

---

## 📝 **Summary**

| Aspect | Status |
|--------|--------|
| **Issue in official repo?** | ❌ No specific issue found |
| **Related issue?** | ⚠️ Issue #6493 (partially related) |
| **Issue addressed?** | ❌ Not addressed |
| **Our solution status** | ✅ Layer 2 implemented, Layer 1 documented |
| **Recommendation** | ✅ Implement Layer 1, consider reporting issue |

---

## ✅ **Conclusion**

**The issue has NOT been addressed in the official repository.**

This means:
- ✅ Our solution is likely the first comprehensive fix for this problem
- ✅ We should implement Layer 1 (Smart Delay) to complete the solution
- ✅ Consider reporting this to help the Onyx community
- ✅ Our fix should work well and won't conflict with existing solutions

**Action Items:**
1. Implement Layer 1 (Smart Delay) from `PRACTICAL-SOLUTION-FIRST-PROMPT.md`
2. Test the complete solution
3. (Optional) Report issue to official repo with our solution as reference

