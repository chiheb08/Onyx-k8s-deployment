# File Upload Feature Improvements for Onyx

## 🎯 **Current Issue**

Users can see their uploaded files and mention them in prompts, but there's **no clear way to delete them** from the main UI. The delete functionality exists in the code but is only accessible in specific contexts (project files, admin interfaces).

---

## 📋 **Current File Management Capabilities**

### **What Works Now:**
1. ✅ **File Upload**: Users can upload files via drag & drop or file picker
2. ✅ **File Mention**: Users can reference files in chat using `@filename`
3. ✅ **Project Files**: Users can manage files within projects (with delete option)
4. ✅ **File Preview**: Users can see file names and status in chat input

### **What's Missing:**
1. ❌ **Personal File Management**: No dedicated interface for managing all user files
2. ❌ **Easy File Deletion**: No obvious way to delete files from main chat interface
3. ❌ **File Organization**: No way to organize files outside of projects
4. ❌ **File Search**: No search functionality for user files
5. ❌ **File Details**: Limited information about file size, upload date, etc.

---

## 🛠️ **Recommended Improvements**

### **1. Add Personal File Management Interface**

Create a dedicated "My Files" section where users can manage all their uploaded files.

#### **Location Options:**
- **Option A**: Add to user profile/settings menu
- **Option B**: Add as a sidebar panel in chat interface
- **Option C**: Add as a dedicated page accessible from main navigation

#### **Features to Include:**
```
My Files Interface:
├── File List View
│   ├── File name
│   ├── File size
│   ├── Upload date
│   ├── Used in projects (count)
│   └── Actions (Delete, Download, Share)
├── Search & Filter
│   ├── Search by filename
│   ├── Filter by file type
│   ├── Filter by upload date
│   └── Filter by usage status
├── Bulk Actions
│   ├── Select multiple files
│   ├── Bulk delete
│   └── Bulk organize
└── Storage Usage
    ├── Total storage used
    ├── Storage limit
    └── Storage breakdown by file type
```

### **2. Improve In-Chat File Management**

Make file deletion more accessible directly from the chat interface.

#### **Current Chat Interface:**
```
[File attachment preview] - No delete option visible
```

#### **Improved Chat Interface:**
```
[File attachment preview] [X Delete] [↓ Download] [ℹ Info]
```

### **3. Add File Context Menu**

Right-click context menu for files with common actions.

#### **Context Menu Options:**
```
Right-click on file:
├── Delete file
├── Download file
├── Copy file link
├── Add to project
├── Remove from project
├── View file details
└── Share file
```

---

## 🔧 **Implementation Guide**

### **Phase 1: Quick Fix - Add Delete Button to Chat Interface**

#### **File: `InputBarPreview.tsx` (Already has delete functionality)**
The file preview in chat input already has a delete button, but it might not be visible enough.

**Current Implementation:**
```typescript
// File: onyx-repo/web/src/app/chat/components/files/InputBarPreview.tsx
<button
  onClick={onDelete}
  className="cursor-pointer border-none bg-accent-background-hovered rounded-full z-10"
>
  <FiX />
</button>
```

**Improvement Needed:**
- Make the delete button more visible
- Add hover effects and tooltips
- Improve accessibility

### **Phase 2: Add Personal File Management Page**

#### **Create New Component: `UserFilesManager.tsx`**

```typescript
// Location: onyx-repo/web/src/app/chat/components/files/UserFilesManager.tsx

interface UserFilesManagerProps {
  onClose?: () => void;
}

export function UserFilesManager({ onClose }: UserFilesManagerProps) {
  const { recentFiles, deleteUserFile } = useProjects();
  const [searchTerm, setSearchTerm] = useState("");
  const [selectedFiles, setSelectedFiles] = useState<string[]>([]);

  return (
    <Dialog open={true} onOpenChange={onClose}>
      <DialogContent className="max-w-4xl max-h-[80vh]">
        <DialogHeader>
          <DialogTitle>My Files</DialogTitle>
          <DialogDescription>
            Manage all your uploaded files
          </DialogDescription>
        </DialogHeader>
        
        {/* Search and Filter Bar */}
        <div className="flex gap-4 mb-4">
          <Input
            placeholder="Search files..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="flex-1"
          />
          <Button variant="outline">Filter</Button>
        </div>

        {/* File List */}
        <ScrollArea className="h-96">
          <div className="space-y-2">
            {filteredFiles.map((file) => (
              <FileRow
                key={file.id}
                file={file}
                isSelected={selectedFiles.includes(file.id)}
                onSelect={(selected) => handleFileSelect(file.id, selected)}
                onDelete={() => deleteUserFile(file.id)}
              />
            ))}
          </div>
        </ScrollArea>

        {/* Bulk Actions */}
        {selectedFiles.length > 0 && (
          <div className="flex gap-2 mt-4">
            <Button 
              variant="destructive" 
              onClick={handleBulkDelete}
            >
              Delete Selected ({selectedFiles.length})
            </Button>
            <Button variant="outline" onClick={handleDeselectAll}>
              Deselect All
            </Button>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
```

#### **Create File Row Component: `FileRow.tsx`**

```typescript
// Location: onyx-repo/web/src/app/chat/components/files/FileRow.tsx

interface FileRowProps {
  file: ProjectFile;
  isSelected: boolean;
  onSelect: (selected: boolean) => void;
  onDelete: () => void;
}

export function FileRow({ file, isSelected, onSelect, onDelete }: FileRowProps) {
  return (
    <div className="flex items-center gap-3 p-3 border rounded-lg hover:bg-accent">
      {/* Checkbox */}
      <Checkbox
        checked={isSelected}
        onCheckedChange={onSelect}
      />
      
      {/* File Icon */}
      <div className="flex-shrink-0">
        <DocumentIcon className="h-6 w-6" />
      </div>
      
      {/* File Info */}
      <div className="flex-1 min-w-0">
        <div className="font-medium truncate">{file.name}</div>
        <div className="text-sm text-muted-foreground">
          {formatFileSize(file.size)} • {formatDate(file.uploadDate)}
        </div>
      </div>
      
      {/* Actions */}
      <div className="flex gap-2">
        <Button
          variant="ghost"
          size="sm"
          onClick={() => downloadFile(file)}
        >
          <Download className="h-4 w-4" />
        </Button>
        <Button
          variant="ghost"
          size="sm"
          onClick={onDelete}
          className="text-destructive hover:text-destructive"
        >
          <Trash2 className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
}
```

### **Phase 3: Add File Management to User Menu**

#### **Update User Settings Modal**

Add a "My Files" tab to the existing user settings modal.

```typescript
// File: onyx-repo/web/src/app/chat/components/modal/UserSettingsModal.tsx

// Add new tab
const tabs = [
  { id: "profile", label: "Profile" },
  { id: "preferences", label: "Preferences" },
  { id: "files", label: "My Files" }, // ← NEW TAB
  { id: "api", label: "API Keys" },
];

// Add tab content
{activeTab === "files" && (
  <div className="space-y-4">
    <h3 className="text-lg font-semibold">File Management</h3>
    <UserFilesManager />
  </div>
)}
```

---

## 🚀 **Quick Implementation Steps**

### **Step 1: Improve Current File Preview (Immediate Fix)**

#### **Update InputBarPreview Component:**

```typescript
// File: onyx-repo/web/src/app/chat/components/files/InputBarPreview.tsx

// Improve the delete button visibility
<button
  onClick={onDelete}
  title="Remove file"
  className="
    cursor-pointer 
    border-none 
    bg-red-500 
    hover:bg-red-600 
    text-white 
    rounded-full 
    p-1 
    z-10 
    transition-colors
  "
>
  <FiX size={14} />
</button>
```

### **Step 2: Add File Management Button to Chat Interface**

#### **Add "Manage Files" Button:**

```typescript
// File: onyx-repo/web/src/app/chat/components/input/ChatInputBar.tsx

// Add button near file upload
<Button
  variant="ghost"
  size="sm"
  onClick={() => setShowFileManager(true)}
  title="Manage my files"
>
  <FolderOpen className="h-4 w-4" />
  My Files
</Button>

{showFileManager && (
  <UserFilesManager onClose={() => setShowFileManager(false)} />
)}
```

### **Step 3: Enhance File List Component**

#### **Update FilesList Component:**

```typescript
// File: onyx-repo/web/src/app/chat/components/files/FilesList.tsx

// Make delete button more prominent
{showRemove && String(f.status).toLowerCase() !== "processing" && (
  <button
    title="Delete file permanently"
    aria-label="Delete file permanently"
    className="
      p-1 
      bg-red-500 
      hover:bg-red-600 
      text-white 
      rounded 
      opacity-0 
      group-hover:opacity-100 
      focus:opacity-100 
      transition-all 
      duration-150
    "
    onClick={(e) => {
      e.stopPropagation();
      if (confirm(`Delete "${f.name}"? This action cannot be undone.`)) {
        onRemove && onRemove(f);
      }
    }}
  >
    <Trash2 className="h-3 w-3" />
  </button>
)}
```

---

## 📱 **UI/UX Improvements**

### **1. Better Visual Feedback**

#### **File Upload States:**
```
States to Show:
├── Uploading (progress bar)
├── Processing (spinner)
├── Ready (checkmark)
├── Error (error icon)
└── Deleted (fade out animation)
```

#### **Delete Confirmation:**
```
Confirmation Dialog:
├── File preview
├── "Are you sure?" message
├── Warning about permanent deletion
├── Cancel / Delete buttons
└── "Don't ask again" option
```

### **2. Keyboard Shortcuts**

#### **Useful Shortcuts:**
```
Keyboard Shortcuts:
├── Ctrl+U: Upload files
├── Delete: Delete selected file
├── Ctrl+A: Select all files
├── Escape: Deselect all
└── Ctrl+F: Search files
```

### **3. Drag & Drop Improvements**

#### **Enhanced Drag & Drop:**
```
Drag & Drop Features:
├── Visual drop zones
├── File type validation
├── Size limit warnings
├── Duplicate file detection
└── Batch upload progress
```

---

## 🔧 **Configuration Changes Needed**

### **1. Update ConfigMap for File Management**

Add file management settings to your ConfigMap:

```yaml
# File: manifests/05-configmap.yaml
data:
  # File Upload Configuration
  MAX_FILE_SIZE_MB: "10"
  ALLOWED_FILE_TYPES: "pdf,doc,docx,txt,md,csv,xlsx,ppt,pptx"
  MAX_FILES_PER_USER: "100"
  ENABLE_FILE_SEARCH: "true"
  ENABLE_BULK_OPERATIONS: "true"
```

### **2. Update API Server for Enhanced File Management**

The API already supports file deletion via:
```
DELETE /api/user/projects/file/{fileId}
```

But you might want to add:
```
GET /api/user/files - List all user files
POST /api/user/files/bulk-delete - Bulk delete files
GET /api/user/files/search - Search user files
GET /api/user/files/stats - Get storage usage stats
```

---

## 🎯 **Priority Implementation Order**

### **High Priority (Immediate):**
1. ✅ **Make delete buttons more visible** in existing file previews
2. ✅ **Add confirmation dialogs** for file deletion
3. ✅ **Improve file upload feedback** (progress, errors)

### **Medium Priority (Next Sprint):**
1. 🔄 **Add "My Files" management interface**
2. 🔄 **Add file search functionality**
3. 🔄 **Add bulk file operations**

### **Low Priority (Future):**
1. 📅 **Add file organization features** (folders, tags)
2. 📅 **Add file sharing capabilities**
3. 📅 **Add advanced file analytics**

---

## 🎉 **Expected User Experience After Improvements**

### **Before (Current):**
- ❌ User uploads file but can't easily delete it
- ❌ No central place to manage files
- ❌ Limited visibility of file status
- ❌ No bulk operations

### **After (Improved):**
- ✅ Clear delete buttons with confirmation
- ✅ Dedicated "My Files" management interface
- ✅ Search and filter capabilities
- ✅ Bulk delete operations
- ✅ Better visual feedback
- ✅ Storage usage information
- ✅ File organization options

---

## 🛠️ **Quick Fix You Can Apply Now**

### **Immediate Solution - Make Delete Buttons More Visible:**

1. **Update the CSS for delete buttons** to make them more prominent
2. **Add confirmation dialogs** before deletion
3. **Add tooltips** explaining what the buttons do
4. **Improve hover states** for better user feedback

### **Code Changes Needed:**

```css
/* Make delete buttons more visible */
.file-delete-button {
  background-color: #ef4444 !important;
  color: white !important;
  opacity: 0.8 !important;
  transition: all 0.2s ease !important;
}

.file-delete-button:hover {
  opacity: 1 !important;
  background-color: #dc2626 !important;
  transform: scale(1.1) !important;
}
```

This will make the existing delete functionality much more discoverable and user-friendly! 🎯
