# Onyx Enterprise File Management System
## Advanced Document Processing & Storage Capabilities

---

## 📁 **Executive Summary**

Onyx's Enterprise File Management System provides a comprehensive, secure, and scalable solution for document processing, storage, and management. Built on private S3 storage with advanced AI-powered processing capabilities, Onyx delivers enterprise-grade file management that ensures data security, compliance, and optimal performance for organizations of all sizes.

---

## 🏗️ **File Management Architecture**

### **Multi-Tier Storage Strategy**

Onyx implements a sophisticated multi-tier storage architecture designed for enterprise use:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   User Upload   │───▶│  API Processing │───▶│  Private S3     │
│   (Frontend)    │    │   (FastAPI)     │    │   Storage       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │  Background     │
                       │  Processing     │
                       │  (Celery)       │
                       └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │  Vector Search  │
                       │  (Vespa)        │
                       └─────────────────┘
```

### **Storage Components**

#### **1. Private S3 Storage**
- **Encryption**: AES-256 server-side encryption
- **Access Control**: IAM-based permissions
- **Versioning**: File version management
- **Lifecycle Policies**: Automated data retention
- **Cross-Region Replication**: Disaster recovery

#### **2. Metadata Database (PostgreSQL)**
- **File Information**: Complete file metadata
- **User Associations**: File ownership tracking
- **Processing Status**: Real-time processing updates
- **Access Logs**: Comprehensive audit trail

#### **3. Vector Search (Vespa)**
- **Semantic Search**: AI-powered document search
- **Real-time Indexing**: Instant search capability
- **Multi-language Support**: Global document processing

---

## 🔧 **File Upload & Processing Pipeline**

### **1. Upload Process**
```typescript
// Frontend file upload implementation
interface FileUploadOptions {
  file: File;
  projectId?: string;
  onProgress?: (progress: number) => void;
  onSuccess?: (fileId: string) => void;
  onError?: (error: string) => void;
}

class FileUploadManager {
  async uploadFile(options: FileUploadOptions): Promise<string> {
    const formData = new FormData();
    formData.append('file', options.file);
    if (options.projectId) {
      formData.append('projectId', options.projectId);
    }

    const response = await fetch('/api/files/upload', {
      method: 'POST',
      body: formData,
      headers: {
        'Authorization': `Bearer ${this.getAuthToken()}`
      }
    });

    if (!response.ok) {
      throw new Error(`Upload failed: ${response.statusText}`);
    }

    const result = await response.json();
    return result.fileId;
  }

  async uploadWithProgress(options: FileUploadOptions): Promise<string> {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      
      xhr.upload.addEventListener('progress', (event) => {
        if (event.lengthComputable) {
          const progress = (event.loaded / event.total) * 100;
          options.onProgress?.(progress);
        }
      });

      xhr.addEventListener('load', () => {
        if (xhr.status === 200) {
          const result = JSON.parse(xhr.responseText);
          options.onSuccess?.(result.fileId);
          resolve(result.fileId);
        } else {
          const error = `Upload failed: ${xhr.statusText}`;
          options.onError?.(error);
          reject(new Error(error));
        }
      });

      xhr.addEventListener('error', () => {
        const error = 'Upload failed: Network error';
        options.onError?.(error);
        reject(new Error(error));
      });

      const formData = new FormData();
      formData.append('file', options.file);
      if (options.projectId) {
        formData.append('projectId', options.projectId);
      }

      xhr.open('POST', '/api/files/upload');
      xhr.setRequestHeader('Authorization', `Bearer ${this.getAuthToken()}`);
      xhr.send(formData);
    });
  }
}
```

### **2. Backend Processing**
```python
# Backend file upload and processing
from fastapi import FastAPI, File, UploadFile, Depends, HTTPException
from fastapi.security import HTTPBearer
from sqlalchemy.orm import Session
from onyx.file_processing import FileProcessor
from onyx.storage import S3FileManager
from onyx.tasks import process_document_task
import uuid

app = FastAPI()
security = HTTPBearer()

@app.post("/api/files/upload")
async def upload_file(
    file: UploadFile = File(...),
    project_id: Optional[str] = None,
    current_user: dict = Depends(verify_token),
    db: Session = Depends(get_db)
):
    """Upload file and initiate processing"""
    
    # Validate file
    if not file.filename:
        raise HTTPException(status_code=400, detail="No file provided")
    
    # Check file size (100MB limit)
    file_content = await file.read()
    if len(file_content) > 100 * 1024 * 1024:  # 100MB
        raise HTTPException(status_code=413, detail="File too large")
    
    # Generate unique file ID
    file_id = str(uuid.uuid4())
    
    # Upload to S3
    s3_key = s3_manager.upload_file(
        file_content, 
        current_user['user_id'], 
        file.filename
    )
    
    # Store metadata in database
    file_record = UserFile(
        id=file_id,
        user_id=current_user['user_id'],
        organization_id=current_user['organization_id'],
        filename=file.filename,
        s3_key=s3_key,
        size=len(file_content),
        content_type=file.content_type,
        project_id=project_id,
        status='uploaded',
        uploaded_at=datetime.utcnow()
    )
    
    db.add(file_record)
    db.commit()
    
    # Queue background processing
    process_document_task.delay(file_id, current_user['user_id'])
    
    return {
        "fileId": file_id,
        "filename": file.filename,
        "size": len(file_content),
        "status": "uploaded"
    }
```

### **3. Background Processing**
```python
# Celery task for document processing
@celery_app.task(bind=True, name='process_document')
def process_document_task(self, file_id: str, user_id: str):
    """Process uploaded document in background"""
    try:
        # Update status to processing
        update_file_status(file_id, 'processing')
        
        # Get file from database
        file_record = get_file_record(file_id, user_id)
        if not file_record:
            raise Exception(f"File {file_id} not found")
        
        # Download file from S3
        file_content = s3_manager.download_file(file_record.s3_key)
        
        # Extract text content based on file type
        text_content = extract_text_from_file(file_content, file_record.content_type)
        
        # Generate embeddings using model server
        embeddings = call_model_server_for_embeddings(text_content)
        
        # Store in Vespa for search
        store_document_in_vespa(
            file_id=file_id,
            user_id=user_id,
            title=file_record.filename,
            content=text_content,
            embeddings=embeddings
        )
        
        # Update status to completed
        update_file_status(file_id, 'completed')
        
        return {'status': 'success', 'file_id': file_id}
        
    except Exception as exc:
        # Update status to failed
        update_file_status(file_id, 'failed')
        
        # Log error
        logger.error(f"Document processing failed for {file_id}: {exc}")
        
        # Retry with exponential backoff
        raise self.retry(exc=exc, countdown=60, max_retries=3)

def extract_text_from_file(file_content: bytes, content_type: str) -> str:
    """Extract text content from various file types"""
    if content_type == 'application/pdf':
        return extract_text_from_pdf(file_content)
    elif content_type in ['application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/msword']:
        return extract_text_from_docx(file_content)
    elif content_type == 'text/plain':
        return file_content.decode('utf-8')
    elif content_type == 'text/markdown':
        return file_content.decode('utf-8')
    else:
        # Try to extract text using general method
        return extract_text_generic(file_content)
```

---

## 🔍 **Advanced Search Capabilities**

### **1. Semantic Search Implementation**
```python
# Semantic search implementation
class DocumentSearchEngine:
    def __init__(self, vespa_client, model_server_client):
        self.vespa = vespa_client
        self.model_server = model_server_client
    
    async def search_documents(
        self, 
        query: str, 
        user_id: str, 
        filters: Optional[Dict] = None,
        limit: int = 20
    ) -> List[SearchResult]:
        """Perform semantic search on user's documents"""
        
        # Generate query embedding
        query_embedding = await self.model_server.generate_embedding(query)
        
        # Build Vespa query
        vespa_query = {
            "yql": "select * from document where user_id = {user_id}",
            "hits": limit,
            "ranking": "semantic_similarity",
            "input.query(embedding)": query_embedding.tolist()
        }
        
        # Add filters if provided
        if filters:
            if 'project_id' in filters:
                vespa_query["yql"] += f" and project_id = '{filters['project_id']}'"
            if 'file_type' in filters:
                vespa_query["yql"] += f" and content_type = '{filters['file_type']}'"
            if 'date_range' in filters:
                start_date = filters['date_range']['start']
                end_date = filters['date_range']['end']
                vespa_query["yql"] += f" and uploaded_at >= {start_date} and uploaded_at <= {end_date}"
        
        # Execute search
        results = await self.vespa.search(vespa_query)
        
        # Format results
        search_results = []
        for hit in results.hits:
            search_results.append(SearchResult(
                file_id=hit.fields['id'],
                filename=hit.fields['title'],
                content_snippet=hit.fields['content'][:200] + "...",
                relevance_score=hit.relevance,
                uploaded_at=hit.fields['uploaded_at']
            ))
        
        return search_results
```

### **2. File Management Interface**
```typescript
// File management UI components
interface FileItem {
  id: string;
  filename: string;
  size: number;
  uploadedAt: Date;
  status: 'uploaded' | 'processing' | 'completed' | 'failed';
  projectId?: string;
  contentType: string;
}

interface FileManagerProps {
  files: FileItem[];
  onDelete: (fileId: string) => void;
  onDownload: (fileId: string) => void;
  onSearch: (query: string) => void;
}

const FileManager: React.FC<FileManagerProps> = ({
  files,
  onDelete,
  onDownload,
  onSearch
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [filteredFiles, setFilteredFiles] = useState(files);

  useEffect(() => {
    if (searchQuery) {
      const filtered = files.filter(file =>
        file.filename.toLowerCase().includes(searchQuery.toLowerCase())
      );
      setFilteredFiles(filtered);
    } else {
      setFilteredFiles(files);
    }
  }, [searchQuery, files]);

  return (
    <div className="file-manager">
      <div className="file-manager-header">
        <h2>My Files</h2>
        <div className="search-bar">
          <input
            type="text"
            placeholder="Search files..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>
      </div>
      
      <div className="file-list">
        {filteredFiles.map(file => (
          <FileItem
            key={file.id}
            file={file}
            onDelete={() => onDelete(file.id)}
            onDownload={() => onDownload(file.id)}
          />
        ))}
      </div>
    </div>
  );
};

const FileItem: React.FC<{
  file: FileItem;
  onDelete: () => void;
  onDownload: () => void;
}> = ({ file, onDelete, onDownload }) => {
  const formatFileSize = (bytes: number) => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'completed': return 'text-green-600';
      case 'processing': return 'text-yellow-600';
      case 'failed': return 'text-red-600';
      default: return 'text-gray-600';
    }
  };

  return (
    <div className="file-item">
      <div className="file-info">
        <div className="file-icon">
          <FileIcon type={file.contentType} />
        </div>
        <div className="file-details">
          <h3 className="file-name">{file.filename}</h3>
          <p className="file-meta">
            {formatFileSize(file.size)} • {file.uploadedAt.toLocaleDateString()}
          </p>
          <p className={`file-status ${getStatusColor(file.status)}`}>
            {file.status.charAt(0).toUpperCase() + file.status.slice(1)}
          </p>
        </div>
      </div>
      
      <div className="file-actions">
        <button
          onClick={onDownload}
          className="btn-download"
          disabled={file.status !== 'completed'}
        >
          Download
        </button>
        <button
          onClick={onDelete}
          className="btn-delete"
        >
          Delete
        </button>
      </div>
    </div>
  );
};
```

---

## 🗂️ **Project-Based File Organization**

### **1. Project Management**
```python
# Project-based file organization
class ProjectManager:
    def __init__(self, db_session: Session):
        self.db = db_session
    
    def create_project(self, user_id: str, name: str, description: str = None) -> str:
        """Create a new project for organizing files"""
        project = Project(
            id=str(uuid.uuid4()),
            user_id=user_id,
            name=name,
            description=description,
            created_at=datetime.utcnow()
        )
        
        self.db.add(project)
        self.db.commit()
        
        return project.id
    
    def add_file_to_project(self, file_id: str, project_id: str, user_id: str) -> bool:
        """Add existing file to project"""
        # Verify file ownership
        file_record = self.db.query(UserFile).filter(
            UserFile.id == file_id,
            UserFile.user_id == user_id
        ).first()
        
        if not file_record:
            return False
        
        # Verify project ownership
        project = self.db.query(Project).filter(
            Project.id == project_id,
            Project.user_id == user_id
        ).first()
        
        if not project:
            return False
        
        # Create project-file association
        project_file = ProjectFile(
            project_id=project_id,
            file_id=file_id,
            added_at=datetime.utcnow()
        )
        
        self.db.add(project_file)
        self.db.commit()
        
        return True
    
    def get_project_files(self, project_id: str, user_id: str) -> List[UserFile]:
        """Get all files in a project"""
        return self.db.query(UserFile).join(ProjectFile).filter(
            ProjectFile.project_id == project_id,
            UserFile.user_id == user_id
        ).all()
    
    def remove_file_from_project(self, file_id: str, project_id: str, user_id: str) -> bool:
        """Remove file from project (doesn't delete the file)"""
        project_file = self.db.query(ProjectFile).join(UserFile).filter(
            ProjectFile.project_id == project_id,
            ProjectFile.file_id == file_id,
            UserFile.user_id == user_id
        ).first()
        
        if project_file:
            self.db.delete(project_file)
            self.db.commit()
            return True
        
        return False
```

### **2. File Sharing & Collaboration**
```python
# File sharing and collaboration features
class FileSharingManager:
    def __init__(self, db_session: Session):
        self.db = db_session
    
    def share_file(self, file_id: str, owner_id: str, shared_with_user_id: str, permissions: str = 'read') -> bool:
        """Share file with another user"""
        # Verify file ownership
        file_record = self.db.query(UserFile).filter(
            UserFile.id == file_id,
            UserFile.user_id == owner_id
        ).first()
        
        if not file_record:
            return False
        
        # Create sharing record
        file_share = FileShare(
            file_id=file_id,
            owner_id=owner_id,
            shared_with_user_id=shared_with_user_id,
            permissions=permissions,
            shared_at=datetime.utcnow()
        )
        
        self.db.add(file_share)
        self.db.commit()
        
        return True
    
    def get_shared_files(self, user_id: str) -> List[UserFile]:
        """Get files shared with user"""
        return self.db.query(UserFile).join(FileShare).filter(
            FileShare.shared_with_user_id == user_id
        ).all()
    
    def revoke_file_access(self, file_id: str, owner_id: str, shared_with_user_id: str) -> bool:
        """Revoke file access for a user"""
        file_share = self.db.query(FileShare).filter(
            FileShare.file_id == file_id,
            FileShare.owner_id == owner_id,
            FileShare.shared_with_user_id == shared_with_user_id
        ).first()
        
        if file_share:
            self.db.delete(file_share)
            self.db.commit()
            return True
        
        return False
```

---

## 🔒 **Security & Access Control**

### **1. File Access Control**
```python
# Comprehensive file access control
class FileAccessController:
    def __init__(self, db_session: Session):
        self.db = db_session
    
    def can_access_file(self, user_id: str, file_id: str) -> bool:
        """Check if user can access specific file"""
        # Check if user owns the file
        owned_file = self.db.query(UserFile).filter(
            UserFile.id == file_id,
            UserFile.user_id == user_id
        ).first()
        
        if owned_file:
            return True
        
        # Check if file is shared with user
        shared_file = self.db.query(FileShare).filter(
            FileShare.file_id == file_id,
            FileShare.shared_with_user_id == user_id
        ).first()
        
        return shared_file is not None
    
    def can_modify_file(self, user_id: str, file_id: str) -> bool:
        """Check if user can modify specific file"""
        # Only file owner can modify
        file_record = self.db.query(UserFile).filter(
            UserFile.id == file_id,
            UserFile.user_id == user_id
        ).first()
        
        return file_record is not None
    
    def can_delete_file(self, user_id: str, file_id: str) -> bool:
        """Check if user can delete specific file"""
        # Only file owner can delete
        return self.can_modify_file(user_id, file_id)
    
    def get_file_s3_key(self, file_id: str, user_id: str) -> Optional[str]:
        """Get S3 key for file if user has access"""
        if self.can_access_file(user_id, file_id):
            file_record = self.db.query(UserFile).filter(
                UserFile.id == file_id
            ).first()
            return file_record.s3_key if file_record else None
        return None
```

### **2. Audit Logging**
```python
# Comprehensive audit logging for file operations
class FileAuditLogger:
    def __init__(self, db_session: Session):
        self.db = db_session
    
    def log_file_operation(
        self, 
        operation: str, 
        file_id: str, 
        user_id: str, 
        details: Dict = None
    ):
        """Log file operation for audit purposes"""
        audit_log = FileAuditLog(
            id=str(uuid.uuid4()),
            operation=operation,
            file_id=file_id,
            user_id=user_id,
            timestamp=datetime.utcnow(),
            details=details or {}
        )
        
        self.db.add(audit_log)
        self.db.commit()
    
    def get_file_audit_trail(self, file_id: str) -> List[FileAuditLog]:
        """Get complete audit trail for a file"""
        return self.db.query(FileAuditLog).filter(
            FileAuditLog.file_id == file_id
        ).order_by(FileAuditLog.timestamp.desc()).all()
    
    def get_user_file_operations(self, user_id: str, limit: int = 100) -> List[FileAuditLog]:
        """Get recent file operations for a user"""
        return self.db.query(FileAuditLog).filter(
            FileAuditLog.user_id == user_id
        ).order_by(FileAuditLog.timestamp.desc()).limit(limit).all()
```

---

## 📊 **Performance & Optimization**

### **1. File Processing Optimization**
```python
# Optimized file processing pipeline
class OptimizedFileProcessor:
    def __init__(self):
        self.processing_queue = Queue()
        self.worker_pool = ThreadPoolExecutor(max_workers=4)
    
    async def process_file_batch(self, file_ids: List[str]) -> Dict[str, str]:
        """Process multiple files in parallel"""
        tasks = []
        for file_id in file_ids:
            task = asyncio.create_task(self.process_single_file(file_id))
            tasks.append(task)
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Format results
        processed_results = {}
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                processed_results[file_ids[i]] = f"Error: {str(result)}"
            else:
                processed_results[file_ids[i]] = result
        
        return processed_results
    
    async def process_single_file(self, file_id: str) -> str:
        """Process a single file asynchronously"""
        try:
            # Get file metadata
            file_record = get_file_record(file_id)
            if not file_record:
                return "File not found"
            
            # Download file from S3
            file_content = await s3_manager.download_file_async(file_record.s3_key)
            
            # Extract text content
            text_content = await extract_text_async(file_content, file_record.content_type)
            
            # Generate embeddings
            embeddings = await generate_embeddings_async(text_content)
            
            # Store in search index
            await store_document_async(file_id, text_content, embeddings)
            
            # Update status
            update_file_status(file_id, 'completed')
            
            return "Processing completed"
            
        except Exception as e:
            update_file_status(file_id, 'failed')
            return f"Processing failed: {str(e)}"
```

### **2. Caching Strategy**
```python
# File metadata caching
class FileMetadataCache:
    def __init__(self, redis_client):
        self.redis = redis_client
        self.cache_ttl = 3600  # 1 hour
    
    def get_file_metadata(self, file_id: str) -> Optional[Dict]:
        """Get file metadata from cache"""
        cache_key = f"file_metadata:{file_id}"
        cached_data = self.redis.get(cache_key)
        
        if cached_data:
            return json.loads(cached_data)
        return None
    
    def set_file_metadata(self, file_id: str, metadata: Dict):
        """Cache file metadata"""
        cache_key = f"file_metadata:{file_id}"
        self.redis.setex(
            cache_key, 
            self.cache_ttl, 
            json.dumps(metadata, default=str)
        )
    
    def invalidate_file_metadata(self, file_id: str):
        """Invalidate file metadata cache"""
        cache_key = f"file_metadata:{file_id}"
        self.redis.delete(cache_key)
    
    def get_user_files(self, user_id: str) -> Optional[List[Dict]]:
        """Get user's files from cache"""
        cache_key = f"user_files:{user_id}"
        cached_data = self.redis.get(cache_key)
        
        if cached_data:
            return json.loads(cached_data)
        return None
    
    def set_user_files(self, user_id: str, files: List[Dict]):
        """Cache user's files"""
        cache_key = f"user_files:{user_id}"
        self.redis.setex(
            cache_key, 
            self.cache_ttl, 
            json.dumps(files, default=str)
        )
```

---

## 🚀 **Enterprise Features**

### **1. Bulk Operations**
```python
# Bulk file operations for enterprise use
class BulkFileOperations:
    def __init__(self, db_session: Session, s3_manager: S3FileManager):
        self.db = db_session
        self.s3 = s3_manager
    
    def bulk_delete_files(self, file_ids: List[str], user_id: str) -> Dict[str, str]:
        """Delete multiple files in bulk"""
        results = {}
        
        for file_id in file_ids:
            try:
                # Verify ownership
                file_record = self.db.query(UserFile).filter(
                    UserFile.id == file_id,
                    UserFile.user_id == user_id
                ).first()
                
                if not file_record:
                    results[file_id] = "File not found or access denied"
                    continue
                
                # Delete from S3
                self.s3.delete_file(file_record.s3_key)
                
                # Remove from database
                self.db.delete(file_record)
                
                # Clean up related data
                self.cleanup_file_references(file_id)
                
                results[file_id] = "Deleted successfully"
                
            except Exception as e:
                results[file_id] = f"Delete failed: {str(e)}"
        
        self.db.commit()
        return results
    
    def bulk_download_files(self, file_ids: List[str], user_id: str) -> str:
        """Create ZIP archive for bulk download"""
        import zipfile
        import tempfile
        
        # Create temporary ZIP file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
        
        with zipfile.ZipFile(temp_file.name, 'w') as zip_file:
            for file_id in file_ids:
                try:
                    # Get file record
                    file_record = self.db.query(UserFile).filter(
                        UserFile.id == file_id,
                        UserFile.user_id == user_id
                    ).first()
                    
                    if file_record:
                        # Download from S3
                        file_content = self.s3.download_file(file_record.s3_key)
                        
                        # Add to ZIP
                        zip_file.writestr(file_record.filename, file_content)
                        
                except Exception as e:
                    logger.error(f"Failed to add {file_id} to ZIP: {e}")
        
        return temp_file.name
```

### **2. File Analytics & Reporting**
```python
# File usage analytics and reporting
class FileAnalytics:
    def __init__(self, db_session: Session):
        self.db = db_session
    
    def get_user_file_stats(self, user_id: str) -> Dict:
        """Get file statistics for a user"""
        total_files = self.db.query(UserFile).filter(
            UserFile.user_id == user_id
        ).count()
        
        total_size = self.db.query(func.sum(UserFile.size)).filter(
            UserFile.user_id == user_id
        ).scalar() or 0
        
        files_by_type = self.db.query(
            UserFile.content_type,
            func.count(UserFile.id)
        ).filter(
            UserFile.user_id == user_id
        ).group_by(UserFile.content_type).all()
        
        recent_uploads = self.db.query(UserFile).filter(
            UserFile.user_id == user_id
        ).order_by(UserFile.uploaded_at.desc()).limit(10).all()
        
        return {
            'total_files': total_files,
            'total_size': total_size,
            'files_by_type': dict(files_by_type),
            'recent_uploads': [
                {
                    'filename': f.filename,
                    'size': f.size,
                    'uploaded_at': f.uploaded_at.isoformat()
                }
                for f in recent_uploads
            ]
        }
    
    def get_organization_file_stats(self, organization_id: str) -> Dict:
        """Get file statistics for an organization"""
        total_files = self.db.query(UserFile).join(User).filter(
            User.organization_id == organization_id
        ).count()
        
        total_size = self.db.query(func.sum(UserFile.size)).join(User).filter(
            User.organization_id == organization_id
        ).scalar() or 0
        
        active_users = self.db.query(func.count(func.distinct(UserFile.user_id))).join(User).filter(
            User.organization_id == organization_id
        ).scalar()
        
        return {
            'total_files': total_files,
            'total_size': total_size,
            'active_users': active_users,
            'average_files_per_user': total_files / active_users if active_users > 0 else 0
        }
```

---

## 🎯 **Why Choose Onyx File Management?**

### **For Enterprise IT Teams:**
- **Secure Storage**: Private S3 with encryption and access controls
- **Scalable Architecture**: Handles millions of files with ease
- **Compliance Ready**: Audit logging and data retention policies
- **Performance Optimized**: Caching and parallel processing

### **For Business Users:**
- **Intuitive Interface**: Easy-to-use file management
- **Powerful Search**: AI-powered semantic search across all files
- **Project Organization**: Organize files by projects and teams
- **Collaboration**: Share files securely with team members

### **For Security Teams:**
- **Data Isolation**: Complete user and organization separation
- **Access Control**: Granular permissions and sharing controls
- **Audit Trail**: Comprehensive logging of all file operations
- **Encryption**: End-to-end encryption for all stored files

---

## 📋 **Getting Started with File Management**

### **1. Upload Your First File**
1. Navigate to the file upload interface
2. Select your file (supports PDF, DOCX, TXT, and more)
3. Choose a project (optional)
4. Click upload and watch real-time progress
5. File is automatically processed and indexed for search

### **2. Organize with Projects**
1. Create a new project for your team or topic
2. Add existing files to the project
3. Share projects with team members
4. Use project-based search and filtering

### **3. Search and Discover**
1. Use the search bar to find files by name
2. Try semantic search for content-based discovery
3. Filter by file type, date, or project
4. Get instant results with relevance scoring

### **4. Manage and Collaborate**
1. Share files with specific users
2. Set appropriate permissions
3. Track file access and modifications
4. Bulk operations for efficiency

---

## 🎉 **Conclusion**

Onyx's Enterprise File Management System provides everything your organization needs for secure, scalable, and intelligent document management. With private S3 storage, AI-powered search, comprehensive security controls, and enterprise-grade features, Onyx delivers a complete solution that grows with your business.

**Ready to transform your document management?** Deploy Onyx today and experience the power of enterprise-grade file management with AI intelligence.

---

*For technical support, custom integrations, or enterprise deployment assistance, contact our team or visit our documentation portal.*
