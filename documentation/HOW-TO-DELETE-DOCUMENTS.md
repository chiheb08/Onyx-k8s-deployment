# How to Delete Documents in Onyx - Practical Guide

## 🎯 **Quick Answer to Your Coworker's Question**

**Yes, you can delete loaded documents when signed in!** The process depends on your role and the type of document you want to delete.

---

## 📋 **Step-by-Step Instructions**

### **For Regular Users (Non-Admin):**

#### **1. Delete Files from a Project/Chat Session**

**Step 1: Open your project or chat session**
```
1. Go to your Onyx dashboard
2. Click on the project or chat session where the file is located
3. Look for the "Project Files" section on the right side
```

**Step 2: Find and delete the file**
```
1. Find the file you want to delete in the project files list
2. Hover over the file card
3. You'll see an "X" button appear in the top-left corner
4. Click the "X" button
5. Confirm deletion in the popup that appears
```

**What happens:**
- File is removed from the project
- File is deleted from your account
- File is no longer available for search

#### **2. Delete Personal Files**

**Step 1: Go to your file management**
```
1. Click on your profile/avatar in the top-right corner
2. Select "Files" or "My Files" from the dropdown
3. You'll see all files you've uploaded
```

**Step 2: Delete the file**
```
1. Find the file you want to delete
2. Click the delete button (trash icon)
3. Confirm deletion in the popup
```

**What happens:**
- File is permanently deleted
- All project associations are removed
- File is removed from search results

### **For Admins and Curators:**

#### **1. Delete Document Sets**

**Step 1: Go to the admin panel**
```
1. Log in as an admin
2. Click on "Admin" in the top navigation
3. Go to "Documents" → "Document Sets"
```

**Step 2: Delete the document set**
```
1. Find the document set you want to delete
2. Click the delete button (trash icon) in the Actions column
3. Confirm deletion in the popup
4. The system will show "Document set scheduled for deletion"
```

**What happens:**
- Document set is marked for deletion
- All documents in the set are scheduled for deletion
- Deletion happens in the background
- Document set is removed from all personas and connectors

#### **2. Delete Connector Documents**

**Step 1: Go to connectors**
```
1. Go to Admin → Connectors
2. Find the connector you want to delete
3. Click "Delete Connector"
```

**Step 2: Confirm deletion**
```
1. Confirm deletion in the popup
2. The system will show "Connector scheduled for deletion"
3. Wait for background processing to complete
```

**What happens:**
- All documents from that connector are deleted
- Connector is removed from the system
- Document sets are updated
- Search index is updated

#### **3. Delete Individual Documents**

**Step 1: Use the document explorer**
```
1. Go to Admin → Documents → Explorer
2. Search for the document you want to delete
3. Click on the document to view details
```

**Step 2: Delete the document**
```
1. Click "Delete Document" button
2. Confirm deletion in the popup
3. Wait for background processing
```

**What happens:**
- Document is permanently deleted
- All chunks and embeddings are removed
- Document is removed from search results
- Storage space is freed

---

## 🔍 **What Types of Documents Can You Delete?**

### **Regular Users Can Delete:**
- ✅ **Project Files**: Files you uploaded to specific projects
- ✅ **Personal Files**: Files in your personal file storage
- ❌ **Connector Documents**: Documents synced from external sources
- ❌ **Document Sets**: Collections of documents (admin only)

### **Admins Can Delete:**
- ✅ **Project Files**: Any user's project files
- ✅ **Personal Files**: Any user's personal files
- ✅ **Connector Documents**: Documents from any connector
- ✅ **Document Sets**: Any document set
- ✅ **Individual Documents**: Any document in the system

### **Curators Can Delete:**
- ✅ **Project Files**: Files they have access to
- ✅ **Personal Files**: Their own personal files
- ✅ **Document Sets**: Document sets they manage
- ❌ **Connector Documents**: Cannot delete connector documents
- ❌ **Connectors**: Cannot delete connectors

---

## ⚠️ **Important Warnings**

### **What Happens When You Delete:**

#### **1. Deletion is Permanent**
- Once deleted, documents cannot be recovered
- All associated data is removed
- No backup or restore option

#### **2. Background Processing**
- Deletion happens in the background
- Documents may still appear in search for a few minutes
- Wait for processing to complete

#### **3. Impact on Search**
- Deleted documents are removed from search results
- Search index is updated automatically
- This can take a few minutes

#### **4. Storage Cleanup**
- File storage is freed after deletion
- This happens in the background
- Storage usage updates after cleanup

---

## 🚨 **Common Issues and Solutions**

### **Issue 1: "Cannot Delete Document" Error**

**Problem:** You get an error when trying to delete a document

**Solutions:**
```
1. Check your permissions:
   - Regular users can only delete their own files
   - Admins can delete any document
   - Curators can delete documents they have access to

2. Check if document is in use:
   - Remove document from all projects
   - Remove document from all personas
   - Wait for any ongoing processing to complete
```

### **Issue 2: "Document Still Appears in Search"**

**Problem:** Document appears in search results after deletion

**Solution:**
```
1. Wait for background processing to complete (5-10 minutes)
2. Refresh the search page
3. Check if deletion was successful in admin panel
4. Contact admin if issue persists
```

### **Issue 3: "Cannot Delete Document Set"**

**Problem:** Admin cannot delete a document set

**Solutions:**
```
1. Remove document set from all personas:
   - Go to Admin → Personas
   - Edit each persona
   - Remove the document set from "Document Sets" section

2. Remove document set from all connectors:
   - Go to Admin → Connectors
   - Edit each connector
   - Remove the document set from "Document Sets" section

3. Wait for any ongoing sync to complete
```

### **Issue 4: "File Still Takes Up Space"**

**Problem:** File appears to still take up storage space

**Solution:**
```
1. Wait for storage cleanup to complete (10-15 minutes)
2. Check storage usage in admin panel
3. Contact admin if issue persists
```

---

## 📊 **Deletion Status and Monitoring**

### **How to Check Deletion Status:**

#### **For Users:**
```
1. Check your project files list
2. Check your personal files list
3. Search for the document to see if it's gone
4. Wait 5-10 minutes for background processing
```

#### **For Admins:**
```
1. Go to Admin → Documents → Explorer
2. Search for the document
3. Check deletion logs in admin panel
4. Monitor background processing status
```

### **Deletion Logs:**
```
- All deletions are logged
- Logs show who deleted what and when
- Logs are available in admin panel
- Logs are retained for 1 year
```

---

## 🎯 **Best Practices**

### **For Regular Users:**

#### **1. File Management:**
- Delete files you no longer need
- Keep projects organized
- Use descriptive file names
- Remove files from projects when done

#### **2. Before Deleting:**
- Make sure you don't need the file
- Check if file is used in other projects
- Consider downloading a backup if important
- Ask team members if file is shared

### **For Admins:**

#### **1. Document Set Management:**
- Regularly review document sets
- Delete unused document sets
- Monitor storage usage
- Check deletion logs regularly

#### **2. Connector Management:**
- Monitor connector health
- Delete unused connectors
- Clean up failed syncs
- Update connector configurations

#### **3. System Maintenance:**
- Monitor storage usage
- Clean up orphaned documents
- Review deletion logs
- Monitor system performance

---

## 📞 **Getting Help**

### **If You Need Help:**

#### **For Regular Users:**
1. Check this guide first
2. Ask your team members
3. Contact your admin
4. Check the troubleshooting section

#### **For Admins:**
1. Check admin documentation
2. Review system logs
3. Contact technical support
4. Check system health metrics

### **Common Questions:**

#### **Q: Can I recover a deleted document?**
**A:** No, deletion is permanent. Always make sure you don't need the document before deleting.

#### **Q: How long does deletion take?**
**A:** User file deletion is immediate. Document set and connector deletion takes 5-15 minutes for background processing.

#### **Q: Can I delete documents from other users?**
**A:** Only if you're an admin. Regular users can only delete their own files.

#### **Q: What happens to search results after deletion?**
**A:** Deleted documents are removed from search results after background processing completes (5-10 minutes).

---

## 🎉 **Summary**

**To answer your coworker's question directly:**

**Yes, you can delete loaded documents when signed in!** Here's how:

1. **For your own files**: Go to your project or file management and click the delete button
2. **For document sets**: Admins can delete them from the admin panel
3. **For connector documents**: Admins can delete entire connectors
4. **For individual documents**: Admins can delete them from the document explorer

**Remember:**
- Deletion is permanent
- Wait for background processing
- Check your permissions
- Ask for help if needed

The system provides different levels of access based on your role, ensuring that users can manage their own content while admins have full control over the system.
