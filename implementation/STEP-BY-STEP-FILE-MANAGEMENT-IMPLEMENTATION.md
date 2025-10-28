# Step-by-Step File Management Implementation for Onyx

## 🎯 **Overview**

This guide provides exact code changes to implement a fully functional and professional file management system in Onyx. All changes are based on existing Onyx components and APIs.

---

## 📋 **Implementation Steps**

### **Step 1: Make Delete Buttons More Visible**

#### **File 1: `onyx-repo/web/src/app/chat/components/projects/ProjectContextPanel.tsx`**

**Location**: Lines 89-98
**Change**: Make delete button more visible and add confirmation

```typescript
// FIND THIS CODE (around line 89):
{!isProcessing && (
  <button
    onClick={handleRemoveFile}
    title="Delete file"
    aria-label="Delete file"
    className="absolute -left-2 -top-2 z-10 h-5 w-5 flex items-center justify-center rounded-[4px] border border-border text-[11px] bg-[#1f1f1f] text-white dark:bg-[#fefcfa] dark:text-black shadow-sm opacity-0 group-hover:opacity-100 focus:opacity-100 pointer-events-none group-hover:pointer-events-auto focus:pointer-events-auto transition-opacity duration-150 hover:opacity-90"
  >
    <X className="h-4 w-4 dark:text-dark-tremor-background-muted" />
  </button>
)}

// REPLACE WITH:
{!isProcessing && (
  <button
    onClick={(e) => {
      e.stopPropagation();
      if (confirm(`Delete "${file.name}"? This action cannot be undone.`)) {
        handleRemoveFile();
      }
    }}
    title="Delete file permanently"
    aria-label="Delete file permanently"
    className="absolute -left-2 -top-2 z-10 h-6 w-6 flex items-center justify-center rounded-full border border-red-300 bg-red-500 text-white shadow-md opacity-85 group-hover:opacity-100 focus:opacity-100 hover:bg-red-600 focus:bg-red-600 transition-all duration-150 hover:scale-110"
  >
    <X className="h-4 w-4" />
  </button>
)}
```

#### **File 2: `onyx-repo/web/src/app/chat/components/files/FilesList.tsx`**

**Location**: Lines 254-267
**Change**: Make delete button more prominent with confirmation

```typescript
// FIND THIS CODE (around line 254):
{showRemove &&
  String(f.status).toLowerCase() !== "processing" && (
    <button
      title="Remove from project"
      aria-label="Remove file from project"
      className="p-0 bg-transparent border-0 outline-none cursor-pointer opacity-0 group-hover:opacity-100 focus:opacity-100 transition-opacity duration-150"
      onClick={(e) => {
        e.stopPropagation();
        onRemove && onRemove(f);
      }}
    >
      <Trash2 className="h-4 w-4 text-neutral-600 hover:text-red-600 dark:text-neutral-400 dark:hover:text-red-400" />
    </button>
  )}

// REPLACE WITH:
{showRemove &&
  String(f.status).toLowerCase() !== "processing" && (
    <button
      title="Delete file permanently"
      aria-label="Delete file permanently"
      className="p-2 bg-red-50 hover:bg-red-100 dark:bg-red-900/20 dark:hover:bg-red-900/40 border border-red-200 dark:border-red-800 rounded-md cursor-pointer opacity-90 group-hover:opacity-100 focus:opacity-100 transition-all duration-150 hover:scale-105"
      onClick={(e) => {
        e.stopPropagation();
        if (confirm(`Delete "${f.name}"? This action cannot be undone.`)) {
          onRemove && onRemove(f);
        }
      }}
    >
      <Trash2 className="h-4 w-4 text-red-600 hover:text-red-700 dark:text-red-400 dark:hover:text-red-300" />
    </button>
  )}
```

---

### **Step 2: Create User Files Manager Component**

#### **File 3: Create `onyx-repo/web/src/app/chat/components/files/UserFilesManager.tsx`**

**Action**: Create new file with this content:

```typescript
"use client";

import React, { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Checkbox } from "@/components/ui/checkbox";
import { Badge } from "@/components/ui/badge";
import { Search, Download, Trash2, FolderOpen, Upload, X } from "lucide-react";
import { useProjectsContext } from "../../projects/ProjectsContext";
import FilesList from "./FilesList";
import FilePicker from "./FilePicker";
import { ProjectFile } from "../../projects/projectsService";
import { formatRelativeTime } from "../projects/project_utils";

interface UserFilesManagerProps {
  open: boolean;
  onClose: () => void;
}

export function UserFilesManager({ open, onClose }: UserFilesManagerProps) {
  const { recentFiles, deleteUserFile, uploadFiles, refreshRecentFiles } = useProjectsContext();
  const [searchTerm, setSearchTerm] = useState("");
  const [selectedFiles, setSelectedFiles] = useState<string[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [showUpload, setShowUpload] = useState(false);

  // Refresh files when modal opens
  useEffect(() => {
    if (open) {
      refreshRecentFiles();
      setSelectedFiles([]);
      setSearchTerm("");
    }
  }, [open, refreshRecentFiles]);

  // Filter files based on search term
  const filteredFiles = recentFiles.filter((file) =>
    file.name.toLowerCase().includes(searchTerm.toLowerCase())
  );

  // Calculate storage usage
  const totalFiles = recentFiles.length;
  const totalSize = recentFiles.reduce((acc, file) => acc + (file.size || 0), 0);
  const formatFileSize = (bytes: number) => {
    if (bytes === 0) return "0 Bytes";
    const k = 1024;
    const sizes = ["Bytes", "KB", "MB", "GB"];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i];
  };

  // Handle file selection
  const handleFileSelect = (fileId: string, selected: boolean) => {
    if (selected) {
      setSelectedFiles([...selectedFiles, fileId]);
    } else {
      setSelectedFiles(selectedFiles.filter(id => id !== fileId));
    }
  };

  // Handle select all
  const handleSelectAll = () => {
    if (selectedFiles.length === filteredFiles.length) {
      setSelectedFiles([]);
    } else {
      setSelectedFiles(filteredFiles.map(f => f.id));
    }
  };

  // Handle bulk delete
  const handleBulkDelete = async () => {
    if (selectedFiles.length === 0) return;
    
    const confirmMessage = `Delete ${selectedFiles.length} file${selectedFiles.length > 1 ? 's' : ''}? This action cannot be undone.`;
    if (!confirm(confirmMessage)) return;

    setIsLoading(true);
    try {
      await Promise.all(selectedFiles.map(fileId => deleteUserFile(fileId)));
      setSelectedFiles([]);
    } catch (error) {
      console.error("Failed to delete files:", error);
      alert("Failed to delete some files. Please try again.");
    } finally {
      setIsLoading(false);
    }
  };

  // Handle single file delete
  const handleSingleDelete = async (file: ProjectFile) => {
    if (!confirm(`Delete "${file.name}"? This action cannot be undone.`)) return;
    
    setIsLoading(true);
    try {
      await deleteUserFile(file.id);
    } catch (error) {
      console.error("Failed to delete file:", error);
      alert("Failed to delete file. Please try again.");
    } finally {
      setIsLoading(false);
    }
  };

  // Handle file upload
  const handleFileUpload = async (files: File[]) => {
    setIsLoading(true);
    try {
      await uploadFiles(files);
      setShowUpload(false);
    } catch (error) {
      console.error("Failed to upload files:", error);
      alert("Failed to upload files. Please try again.");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onClose}>
      <DialogContent className="max-w-4xl max-h-[85vh] flex flex-col">
        <DialogHeader>
          <div className="flex items-center gap-3">
            <FolderOpen className="h-8 w-8 text-blue-600" />
            <div>
              <DialogTitle className="text-xl">My Files</DialogTitle>
              <DialogDescription>
                Manage all your uploaded files • {totalFiles} files • {formatFileSize(totalSize)}
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        {/* Search and Actions Bar */}
        <div className="flex gap-4 items-center py-4 border-b">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-gray-400" />
            <Input
              placeholder="Search files..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-10"
            />
          </div>
          <Button
            variant="outline"
            onClick={() => setShowUpload(true)}
            className="flex items-center gap-2"
          >
            <Upload className="h-4 w-4" />
            Upload Files
          </Button>
        </div>

        {/* Bulk Actions */}
        {filteredFiles.length > 0 && (
          <div className="flex items-center gap-4 py-2">
            <div className="flex items-center gap-2">
              <Checkbox
                checked={selectedFiles.length === filteredFiles.length && filteredFiles.length > 0}
                onCheckedChange={handleSelectAll}
              />
              <span className="text-sm text-gray-600">
                Select All ({selectedFiles.length} of {filteredFiles.length} selected)
              </span>
            </div>
            {selectedFiles.length > 0 && (
              <Button
                variant="destructive"
                size="sm"
                onClick={handleBulkDelete}
                disabled={isLoading}
                className="flex items-center gap-2"
              >
                <Trash2 className="h-4 w-4" />
                Delete Selected ({selectedFiles.length})
              </Button>
            )}
          </div>
        )}

        {/* Files List */}
        <ScrollArea className="flex-1 min-h-0">
          {filteredFiles.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-12 text-center">
              <FolderOpen className="h-16 w-16 text-gray-300 mb-4" />
              <h3 className="text-lg font-medium text-gray-900 mb-2">
                {searchTerm ? "No files found" : "No files uploaded"}
              </h3>
              <p className="text-gray-500 mb-4">
                {searchTerm 
                  ? `No files match "${searchTerm}"`
                  : "Upload your first file to get started"
                }
              </p>
              {!searchTerm && (
                <Button onClick={() => setShowUpload(true)} className="flex items-center gap-2">
                  <Upload className="h-4 w-4" />
                  Upload Files
                </Button>
              )}
            </div>
          ) : (
            <div className="space-y-2 p-2">
              {filteredFiles.map((file) => (
                <FileRow
                  key={file.id}
                  file={file}
                  isSelected={selectedFiles.includes(file.id)}
                  onSelect={(selected) => handleFileSelect(file.id, selected)}
                  onDelete={() => handleSingleDelete(file)}
                  disabled={isLoading}
                />
              ))}
            </div>
          )}
        </ScrollArea>

        {/* Upload Modal */}
        {showUpload && (
          <div className="absolute inset-0 bg-black/50 flex items-center justify-center z-50">
            <div className="bg-white dark:bg-gray-800 rounded-lg p-6 max-w-md w-full mx-4">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold">Upload Files</h3>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setShowUpload(false)}
                >
                  <X className="h-4 w-4" />
                </Button>
              </div>
              <FilePicker
                onFileUpload={handleFileUpload}
                disabled={isLoading}
              />
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

// File Row Component
interface FileRowProps {
  file: ProjectFile;
  isSelected: boolean;
  onSelect: (selected: boolean) => void;
  onDelete: () => void;
  disabled: boolean;
}

function FileRow({ file, isSelected, onSelect, onDelete, disabled }: FileRowProps) {
  const getFileExtension = (filename: string) => {
    const ext = filename.split('.').pop()?.toLowerCase() || '';
    if (ext === 'txt') return 'PLAINTEXT';
    return ext.toUpperCase();
  };

  const formatFileSize = (bytes: number) => {
    if (bytes === 0) return "0 Bytes";
    const k = 1024;
    const sizes = ["Bytes", "KB", "MB", "GB"];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i];
  };

  return (
    <div className="flex items-center gap-3 p-3 border border-gray-200 dark:border-gray-700 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors">
      {/* Checkbox */}
      <Checkbox
        checked={isSelected}
        onCheckedChange={onSelect}
        disabled={disabled}
      />
      
      {/* File Icon */}
      <div className="flex-shrink-0 w-10 h-10 bg-blue-100 dark:bg-blue-900/30 rounded-lg flex items-center justify-center">
        <span className="text-xs font-medium text-blue-700 dark:text-blue-300">
          {getFileExtension(file.name).slice(0, 3)}
        </span>
      </div>
      
      {/* File Info */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 mb-1">
          <h4 className="font-medium text-gray-900 dark:text-gray-100 truncate">
            {file.name}
          </h4>
          <Badge variant="secondary" className="text-xs">
            {getFileExtension(file.name)}
          </Badge>
        </div>
        <div className="flex items-center gap-4 text-sm text-gray-500 dark:text-gray-400">
          <span>{formatFileSize(file.size || 0)}</span>
          <span>•</span>
          <span>{formatRelativeTime(new Date(file.created_at))}</span>
          {file.status && (
            <>
              <span>•</span>
              <Badge 
                variant={file.status === 'completed' ? 'default' : 'secondary'}
                className="text-xs"
              >
                {file.status}
              </Badge>
            </>
          )}
        </div>
      </div>
      
      {/* Actions */}
      <div className="flex gap-2">
        <Button
          variant="ghost"
          size="sm"
          onClick={onDelete}
          disabled={disabled}
          className="text-red-600 hover:text-red-700 hover:bg-red-50 dark:hover:bg-red-900/20"
        >
          <Trash2 className="h-4 w-4" />
        </Button>
      </div>
    </div>
  );
}

export default UserFilesManager;
```

---

### **Step 3: Add File Management to User Settings**

#### **File 4: `onyx-repo/web/src/app/chat/components/modal/UserSettingsModal.tsx`**

**Location**: Lines 33 and 315-350
**Changes**: Add "files" section type and tab

```typescript
// FIND THIS LINE (around line 33):
type SettingsSection = "settings" | "password" | "connectors";

// REPLACE WITH:
type SettingsSection = "settings" | "password" | "connectors" | "files";
```

**Location**: Lines 315-350
**Change**: Add Files tab to navigation

```typescript
// FIND THIS CODE (around line 315):
{(showPasswordSection || hasConnectors) && (
  <nav>
    <ul className="flex space-x-2">
      <li>
        <Button
          tertiary
          active={activeSection === "settings"}
          onClick={() => setActiveSection("settings")}
        >
          Settings
        </Button>
      </li>
      {showPasswordSection && (
        <li>
          <Button
            tertiary
            active={activeSection === "password"}
            onClick={() => setActiveSection("password")}
          >
            Password
          </Button>
        </li>
      )}
      {hasConnectors && (
        <li>
          <Button
            tertiary
            active={activeSection === "connectors"}
            onClick={() => setActiveSection("connectors")}
          >
            Connectors
          </Button>
        </li>
      )}
    </ul>
  </nav>
)}

// REPLACE WITH:
{(showPasswordSection || hasConnectors || true) && (
  <nav>
    <ul className="flex space-x-2">
      <li>
        <Button
          tertiary
          active={activeSection === "settings"}
          onClick={() => setActiveSection("settings")}
        >
          Settings
        </Button>
      </li>
      {showPasswordSection && (
        <li>
          <Button
            tertiary
            active={activeSection === "password"}
            onClick={() => setActiveSection("password")}
          >
            Password
          </Button>
        </li>
      )}
      <li>
        <Button
          tertiary
          active={activeSection === "files"}
          onClick={() => setActiveSection("files")}
        >
          My Files
        </Button>
      </li>
      {hasConnectors && (
        <li>
          <Button
            tertiary
            active={activeSection === "connectors"}
            onClick={() => setActiveSection("connectors")}
          >
            Connectors
          </Button>
        </li>
      )}
    </ul>
  </nav>
)}
```

**Location**: Add import at the top of the file (around line 1-31)

```typescript
// ADD THIS IMPORT (around line 31):
import { useProjectsContext } from "../../projects/ProjectsContext";
import FilesList from "../files/FilesList";
```

**Location**: Add files section content (find the end of settings sections, around line 700)

```typescript
// FIND THE END OF THE SETTINGS SECTIONS (after connectors section)
// ADD THIS BEFORE THE CLOSING </div>:

{activeSection === "files" && (
  <div className="space-y-6">
    <div>
      <h3 className="text-lg font-medium mb-4">File Management</h3>
      <p className="text-sm text-gray-600 dark:text-gray-400 mb-6">
        Manage all your uploaded files. You can search, delete, and organize your files here.
      </p>
      <UserFilesContent />
    </div>
  </div>
)}
```

**Location**: Add UserFilesContent component before the main component (around line 38)

```typescript
// ADD THIS COMPONENT BEFORE THE MAIN UserSettings COMPONENT:
function UserFilesContent() {
  const { recentFiles, deleteUserFile } = useProjectsContext();
  
  return (
    <div className="space-y-4">
      <div className="bg-gray-50 dark:bg-gray-800/50 rounded-lg p-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm font-medium">Storage Usage</span>
          <span className="text-sm text-gray-600 dark:text-gray-400">
            {recentFiles.length} files
          </span>
        </div>
        <div className="text-xs text-gray-500 dark:text-gray-400">
          Total size: {recentFiles.reduce((acc, file) => acc + (file.size || 0), 0) > 0 
            ? `${(recentFiles.reduce((acc, file) => acc + (file.size || 0), 0) / 1024 / 1024).toFixed(2)} MB`
            : '0 MB'
          }
        </div>
      </div>
      
      <FilesList
        recentFiles={recentFiles}
        showRemove={true}
        onRemove={async (file) => {
          if (confirm(`Delete "${file.name}"? This action cannot be undone.`)) {
            await deleteUserFile(file.id);
          }
        }}
        className="max-h-96"
      />
    </div>
  );
}
```

---

### **Step 4: Add "My Files" Button to Chat Interface**

#### **File 5: Find and modify the main chat input component**

**Note**: The exact file may vary, but look for the main chat input area. Common locations:
- `onyx-repo/web/src/app/chat/components/input/ChatInputBar.tsx`
- `onyx-repo/web/src/app/chat/components/input/SimplifiedChatInputBar.tsx`
- `onyx-repo/web/src/app/chat/page.tsx`

**Search for**: File upload button or input area
**Add**: "My Files" button near the file upload functionality

```typescript
// ADD THESE IMPORTS AT THE TOP:
import { useState } from "react";
import { FolderOpen } from "lucide-react";
import UserFilesManager from "../files/UserFilesManager";

// ADD THIS STATE VARIABLE IN THE COMPONENT:
const [showFilesManager, setShowFilesManager] = useState(false);

// ADD THIS BUTTON NEAR THE FILE UPLOAD BUTTON:
<Button
  variant="outline"
  size="sm"
  onClick={() => setShowFilesManager(true)}
  className="flex items-center gap-2"
  title="Manage my files"
>
  <FolderOpen className="h-4 w-4" />
  My Files
</Button>

// ADD THIS COMPONENT AT THE END OF THE RETURN STATEMENT:
{showFilesManager && (
  <UserFilesManager
    open={showFilesManager}
    onClose={() => setShowFilesManager(false)}
  />
)}
```

---

### **Step 5: Add Missing UI Components (if needed)**

#### **File 6: Check if Badge component exists**

**Location**: `onyx-repo/web/src/components/ui/badge.tsx`

If this file doesn't exist, create it:

```typescript
import * as React from "react"
import { cva, type VariantProps } from "class-variance-authority"
import { cn } from "@/lib/utils"

const badgeVariants = cva(
  "inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2",
  {
    variants: {
      variant: {
        default:
          "border-transparent bg-primary text-primary-foreground hover:bg-primary/80",
        secondary:
          "border-transparent bg-secondary text-secondary-foreground hover:bg-secondary/80",
        destructive:
          "border-transparent bg-destructive text-destructive-foreground hover:bg-destructive/80",
        outline: "text-foreground",
      },
    },
    defaultVariants: {
      variant: "default",
    },
  }
)

export interface BadgeProps
  extends React.HTMLAttributes<HTMLDivElement>,
    VariantProps<typeof badgeVariants> {}

function Badge({ className, variant, ...props }: BadgeProps) {
  return (
    <div className={cn(badgeVariants({ variant }), className)} {...props} />
  )
}

export { Badge, badgeVariants }
```

#### **File 7: Check if Checkbox component exists**

**Location**: `onyx-repo/web/src/components/ui/checkbox.tsx`

If this file doesn't exist, create it:

```typescript
"use client"

import * as React from "react"
import * as CheckboxPrimitive from "@radix-ui/react-checkbox"
import { Check } from "lucide-react"
import { cn } from "@/lib/utils"

const Checkbox = React.forwardRef<
  React.ElementRef<typeof CheckboxPrimitive.Root>,
  React.ComponentPropsWithoutRef<typeof CheckboxPrimitive.Root>
>(({ className, ...props }, ref) => (
  <CheckboxPrimitive.Root
    ref={ref}
    className={cn(
      "peer h-4 w-4 shrink-0 rounded-sm border border-primary ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 data-[state=checked]:bg-primary data-[state=checked]:text-primary-foreground",
      className
    )}
    {...props}
  >
    <CheckboxPrimitive.Indicator
      className={cn("flex items-center justify-center text-current")}
    >
      <Check className="h-4 w-4" />
    </CheckboxPrimitive.Indicator>
  </CheckboxPrimitive.Root>
))
Checkbox.displayName = CheckboxPrimitive.Root.displayName

export { Checkbox }
```

---

## 🚀 **Summary of Changes**

### **Files Modified:**
1. ✅ **ProjectContextPanel.tsx** - Made delete buttons visible with confirmation
2. ✅ **FilesList.tsx** - Enhanced delete buttons with better styling
3. ✅ **UserFilesManager.tsx** - NEW: Complete file management interface
4. ✅ **UserSettingsModal.tsx** - Added "My Files" tab
5. ✅ **Chat Input Component** - Added "My Files" button
6. ✅ **badge.tsx** - NEW: Badge component (if missing)
7. ✅ **checkbox.tsx** - NEW: Checkbox component (if missing)

### **Features Added:**
- ✅ **Visible delete buttons** with confirmation dialogs
- ✅ **Professional file management interface** with search and bulk operations
- ✅ **File management in user settings**
- ✅ **"My Files" button** in chat interface
- ✅ **Storage usage display**
- ✅ **Bulk file selection and deletion**
- ✅ **File search functionality**
- ✅ **Professional styling** with proper hover states and animations

### **Total Implementation Time**: 6-10 hours
### **Difficulty Level**: Medium (mostly UI integration)
### **Backend Changes Required**: None (all APIs already exist)

---

## 🎯 **Next Steps**

1. **Apply all the code changes** listed above
2. **Test the functionality** in your development environment
3. **Adjust styling** if needed to match your theme
4. **Push to GitHub** once everything works

This implementation provides a **fully professional file management system** that integrates seamlessly with Onyx's existing architecture! 🚀
