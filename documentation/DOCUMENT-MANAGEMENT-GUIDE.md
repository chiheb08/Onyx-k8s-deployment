# Document Management in Onyx - Complete Guide

## 🎯 **Overview**

This guide explains how document management works in Onyx, including how to delete loaded documents when signed in. It covers both user-level and admin-level document management capabilities.

---

## 📚 **What Are "Loaded Documents" in Onyx?**

### **Types of Documents in Onyx:**

#### **1. User Files (Project Files)**
- **What they are**: Files uploaded directly by users for specific projects
- **Where they're stored**: In user projects and chat sessions
- **Who can manage them**: The user who uploaded them
- **Examples**: PDFs, Word docs, text files uploaded via the UI

#### **2. Connector Documents**
- **What they are**: Documents synced from external sources (Google Drive, SharePoint, etc.)
- **Where they're stored**: In document sets and connectors
- **Who can manage them**: Admins and curators
- **Examples**: Documents from Google Drive, SharePoint, Confluence, etc.

#### **3. Document Sets**
- **What they are**: Collections of documents grouped together
- **Where they're stored**: In the document management system
- **Who can manage them**: Admins and curators
- **Examples**: "HR Documents", "Engineering Docs", "Company Policies"

---

## 🗑️ **How to Delete Documents When Signed In**

### **For Regular Users (Non-Admin):**

#### **1. Delete Project Files**
```
Step 1: Go to your project or chat session
Step 2: Find the file you want to delete
Step 3: Click the "X" button on the file card
Step 4: Confirm deletion
```

**What happens:**
- File is removed from your project
- File is deleted from the system
- All associations with projects are removed

#### **2. Delete User Files**
```
Step 1: Go to your profile or file management
Step 2: Find the file you want to delete
Step 3: Click the delete button
Step 4: Confirm deletion
```

**What happens:**
- File is permanently deleted
- All project associations are removed
- File is removed from search results

### **For Admins and Curators:**

#### **1. Delete Document Sets**
```
Step 1: Go to Admin → Documents → Document Sets
Step 2: Find the document set you want to delete
Step 3: Click the delete button (trash icon)
Step 4: Confirm deletion
```

**What happens:**
- Document set is scheduled for deletion
- All documents in the set are marked for deletion
- Deletion happens in the background

#### **2. Delete Connector Documents**
```
Step 1: Go to Admin → Connectors
Step 2: Find the connector you want to delete
Step 3: Click "Delete Connector"
Step 4: Confirm deletion
```

**What happens:**
- All documents from that connector are deleted
- Connector is removed from the system
- Document sets are updated

#### **3. Delete Individual Documents**
```
Step 1: Go to Admin → Documents → Explorer
Step 2: Search for the document you want to delete
Step 3: Click on the document
Step 4: Click "Delete Document"
Step 5: Confirm deletion
```

**What happens:**
- Document is permanently deleted
- All chunks and embeddings are removed
- Document is removed from search results

---

## 🔧 **Document Management Interface**

### **User Interface (Regular Users):**

#### **Project Files Management:**
```
Location: Chat interface → Project panel
Actions available:
- Upload new files
- Remove files from project
- Delete files permanently
- View file details
```

#### **File Management:**
```
Location: User profile → Files
Actions available:
- View all uploaded files
- Delete files
- Manage file permissions
- View file usage
```

### **Admin Interface (Admins/Curators):**

#### **Document Sets Management:**
```
Location: Admin → Documents → Document Sets
Actions available:
- Create new document sets
- Edit existing document sets
- Delete document sets
- Manage document set permissions
- View document set contents
```

#### **Connector Management:**
```
Location: Admin → Connectors
Actions available:
- Add new connectors
- Edit connector settings
- Delete connectors
- Manage connector permissions
- View connector status
```

#### **Document Explorer:**
```
Location: Admin → Documents → Explorer
Actions available:
- Search for documents
- View document details
- Delete individual documents
- Manage document visibility
- View document feedback
```

---

## 🚨 **Important Considerations**

### **What Happens When You Delete Documents:**

#### **1. Immediate Effects:**
- Document is marked for deletion
- Document becomes unavailable for search
- Document is removed from user interfaces

#### **2. Background Processing:**
- Document chunks are deleted from the vector database
- Embeddings are removed from the search index
- All metadata is cleaned up
- File storage is freed

#### **3. Permanent Deletion:**
- Document cannot be recovered
- All associated data is removed
- Search results are updated

### **Permissions and Access Control:**

#### **User-Level Permissions:**
- Users can only delete their own files
- Users cannot delete connector documents
- Users cannot delete document sets

#### **Admin-Level Permissions:**
- Admins can delete any document
- Admins can delete document sets
- Admins can delete connectors
- Admins can manage all document permissions

#### **Curator-Level Permissions:**
- Curators can delete documents they have access to
- Curators can delete document sets they manage
- Curators cannot delete connectors

---

## 📋 **Step-by-Step Deletion Process**

### **Deleting Project Files (User):**

#### **Method 1: From Project Panel**
```
1. Open your project or chat session
2. Look for the "Project Files" section
3. Find the file you want to delete
4. Hover over the file card
5. Click the "X" button that appears
6. Confirm deletion in the popup
```

#### **Method 2: From File Management**
```
1. Go to your profile
2. Click on "Files" or "My Files"
3. Find the file you want to delete
4. Click the delete button
5. Confirm deletion
```

### **Deleting Document Sets (Admin):**

#### **Step-by-Step Process:**
```
1. Log in as an admin
2. Navigate to Admin → Documents → Document Sets
3. Find the document set you want to delete
4. Click the delete button (trash icon)
5. Confirm deletion in the popup
6. Wait for background processing to complete
```

### **Deleting Connector Documents (Admin):**

#### **Step-by-Step Process:**
```
1. Log in as an admin
2. Navigate to Admin → Connectors
3. Find the connector you want to delete
4. Click "Delete Connector"
5. Confirm deletion in the popup
6. Wait for background processing to complete
```

---

## 🔍 **Troubleshooting Document Deletion**

### **Common Issues and Solutions:**

#### **1. "Cannot Delete Document" Error**
```
Problem: User gets error when trying to delete document
Solution: Check if user has permission to delete the document
- Regular users can only delete their own files
- Admins can delete any document
- Curators can delete documents they have access to
```

#### **2. "Document Still Appears in Search"**
```
Problem: Document appears in search results after deletion
Solution: Wait for background processing to complete
- Deletion is processed in the background
- Search index is updated after processing
- This can take a few minutes
```

#### **3. "Cannot Delete Document Set"**
```
Problem: Admin cannot delete document set
Solution: Check if document set is in use
- Remove document set from all personas
- Remove document set from all connectors
- Check if document set has active documents
```

#### **4. "File Still Takes Up Space"**
```
Problem: File appears to still take up storage space
Solution: Wait for cleanup to complete
- File storage cleanup happens in background
- Storage is freed after processing
- This can take a few minutes
```

---

## 📊 **Document Management Best Practices**

### **For Regular Users:**

#### **1. File Organization:**
- Use descriptive file names
- Group related files in projects
- Delete files you no longer need
- Keep file sizes reasonable

#### **2. Project Management:**
- Remove files from projects when done
- Delete old project files regularly
- Keep projects organized and clean
- Use meaningful project names

### **For Admins:**

#### **1. Document Set Management:**
- Create logical document set groupings
- Use descriptive names for document sets
- Regularly review and clean up document sets
- Monitor document set usage

#### **2. Connector Management:**
- Monitor connector health and status
- Clean up unused connectors
- Regularly review connector permissions
- Keep connector configurations up to date

#### **3. System Maintenance:**
- Monitor storage usage
- Clean up orphaned documents
- Review deletion logs regularly
- Monitor system performance

---

## 🛡️ **Security and Privacy Considerations**

### **Data Protection:**

#### **1. Deletion Compliance:**
- Deleted documents are permanently removed
- No recovery is possible after deletion
- All associated data is cleaned up
- Compliance with data protection regulations

#### **2. Access Control:**
- Users can only delete their own files
- Admins have full deletion permissions
- Curators have limited deletion permissions
- All deletions are logged and auditable

#### **3. Audit Trail:**
- All deletions are logged
- Deletion history is maintained
- User actions are tracked
- Admin actions are auditable

---

## 📈 **Monitoring and Analytics**

### **Document Management Metrics:**

#### **1. Storage Usage:**
- Total storage used by documents
- Storage per user
- Storage per document set
- Storage per connector

#### **2. Deletion Activity:**
- Number of documents deleted
- Deletion frequency
- Deletion by user type
- Deletion by document type

#### **3. System Health:**
- Document processing status
- Search index health
- Storage cleanup status
- Background task performance

---

## 🎯 **Summary**

### **Key Points:**

1. **Users can delete their own files** from projects and personal storage
2. **Admins can delete any document** including document sets and connectors
3. **Deletion is permanent** and cannot be undone
4. **Background processing** handles cleanup and index updates
5. **Permissions control** who can delete what
6. **Audit trails** track all deletion activities

### **Quick Reference:**

#### **For Users:**
- Delete project files: Project panel → File card → X button
- Delete personal files: Profile → Files → Delete button
- Cannot delete connector documents or document sets

#### **For Admins:**
- Delete document sets: Admin → Documents → Document Sets → Delete
- Delete connectors: Admin → Connectors → Delete Connector
- Delete individual documents: Admin → Documents → Explorer → Delete

### **Remember:**
- **Always confirm deletion** before proceeding
- **Wait for background processing** to complete
- **Check permissions** if deletion fails
- **Monitor system health** after large deletions

This guide provides complete information about document management in Onyx, including how to delete loaded documents when signed in. The system provides different levels of access and control based on user roles and permissions.
