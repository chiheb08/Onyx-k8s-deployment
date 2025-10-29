# Onyx Technical Architecture Deep Dive
## Implementation Details & Technical Specifications

---

## 🏗️ **System Architecture Overview**

Onyx is built on a modern, cloud-native microservices architecture designed for enterprise-scale deployments. The system leverages Kubernetes/OpenShift for orchestration, PostgreSQL for relational data, Redis for caching and task queuing, Vespa for vector search, and private S3 for file storage.

---

## 🔧 **Core Components Technical Details**

### **1. API Server (FastAPI)**
```python
# Core API server implementation
from fastapi import FastAPI, Depends, HTTPException
from fastapi.security import HTTPBearer
from sqlalchemy.orm import Session
from onyx.db.models import User, ChatSession, Document
from onyx.auth.jwt_handler import verify_token

app = FastAPI(title="Onyx API Server", version="1.0.0")

@app.get("/api/chat/sessions")
async def get_chat_sessions(
    current_user: User = Depends(verify_token),
    db: Session = Depends(get_db)
):
    """Get user's chat sessions with automatic data isolation"""
    return db.query(ChatSession).filter(
        ChatSession.user_id == current_user.id
    ).all()
```

**Technical Specifications:**
- **Framework**: FastAPI with async/await support
- **Authentication**: JWT-based with Redis session storage
- **Database**: SQLAlchemy ORM with PostgreSQL
- **API Documentation**: Automatic OpenAPI/Swagger generation
- **Rate Limiting**: Built-in rate limiting and throttling
- **CORS**: Configurable cross-origin resource sharing

### **2. Web Server (Next.js)**
```typescript
// Frontend session management
import { createContext, useContext, useEffect, useState } from 'react';

interface SessionContextType {
  user: User | null;
  session: Session | null;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  isAuthenticated: boolean;
}

export const SessionContext = createContext<SessionContextType | null>(null);

export const useSession = () => {
  const context = useContext(SessionContext);
  if (!context) {
    throw new Error('useSession must be used within SessionProvider');
  }
  return context;
};
```

**Technical Specifications:**
- **Framework**: Next.js 14 with App Router
- **State Management**: React Context + Zustand
- **Authentication**: Client-side JWT handling
- **UI Components**: Tailwind CSS + shadcn/ui
- **Type Safety**: Full TypeScript implementation
- **Performance**: Server-side rendering and static generation

### **3. Database Layer (PostgreSQL)**
```sql
-- User data isolation with Row Level Security
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    organization_id UUID NOT NULL REFERENCES organizations(id),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Create policy for user data isolation
CREATE POLICY user_isolation ON users
    FOR ALL TO authenticated
    USING (id = current_user_id());

-- Chat sessions with automatic user isolation
CREATE TABLE chat_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id),
    title VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Enable RLS and create policy
ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_session_isolation ON chat_sessions
    FOR ALL TO authenticated
    USING (user_id = current_user_id());
```

**Database Features:**
- **Row Level Security (RLS)**: Database-level data isolation
- **Foreign Key Constraints**: Referential integrity enforcement
- **Cascading Deletes**: Automatic cleanup of related data
- **Indexing Strategy**: Optimized indexes for performance
- **Backup & Recovery**: Automated backup with point-in-time recovery
- **Connection Pooling**: Efficient database connection management

### **4. Cache & Session Store (Redis)**
```python
# Redis session management implementation
import redis
import json
from datetime import datetime, timedelta
from typing import Optional, Dict, Any

class SessionManager:
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client
        self.session_timeout = 86400  # 24 hours
    
    def create_session(self, user_id: str, organization_id: str) -> str:
        """Create a new user session with secure token"""
        session_id = self._generate_secure_token()
        session_data = {
            'user_id': user_id,
            'organization_id': organization_id,
            'created_at': datetime.utcnow().isoformat(),
            'expires_at': (datetime.utcnow() + timedelta(seconds=self.session_timeout)).isoformat(),
            'last_activity': datetime.utcnow().isoformat()
        }
        
        # Store session with expiration
        self.redis.setex(
            f"session:{session_id}",
            self.session_timeout,
            json.dumps(session_data)
        )
        
        return session_id
    
    def get_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Retrieve session data and update last activity"""
        session_key = f"session:{session_id}"
        session_data = self.redis.get(session_key)
        
        if session_data:
            session = json.loads(session_data)
            # Update last activity
            session['last_activity'] = datetime.utcnow().isoformat()
            self.redis.setex(session_key, self.session_timeout, json.dumps(session))
            return session
        
        return None
    
    def invalidate_session(self, session_id: str) -> bool:
        """Invalidate a specific session"""
        return bool(self.redis.delete(f"session:{session_id}"))
    
    def invalidate_user_sessions(self, user_id: str) -> int:
        """Invalidate all sessions for a user"""
        pattern = f"session:*"
        keys = self.redis.keys(pattern)
        deleted_count = 0
        
        for key in keys:
            session_data = self.redis.get(key)
            if session_data:
                session = json.loads(session_data)
                if session.get('user_id') == user_id:
                    self.redis.delete(key)
                    deleted_count += 1
        
        return deleted_count
```

**Redis Configuration:**
- **Persistence**: RDB + AOF for data durability
- **Memory Management**: LRU eviction policy
- **Clustering**: Redis Cluster for high availability
- **Security**: Password authentication and TLS encryption
- **Monitoring**: Redis monitoring and alerting

### **5. Vector Search Engine (Vespa)**
```yaml
# Vespa application configuration
application:
  name: onyx-search
  version: "1.0"

search:
  definitions:
    document:
      name: "document"
      fields:
        - name: "id"
          type: "string"
          indexing: attribute | summary
        - name: "user_id"
          type: "string"
          indexing: attribute | summary
        - name: "organization_id"
          type: "string"
          indexing: attribute | summary
        - name: "title"
          type: "string"
          indexing: index | summary
        - name: "content"
          type: "string"
          indexing: index | summary
        - name: "embedding"
          type: "tensor<float>(x[384])"
          indexing: attribute | index
          attribute:
            distance-metric: "angular"
```

**Vespa Features:**
- **Semantic Search**: AI-powered document search using embeddings
- **Real-time Indexing**: Instant search capability
- **Multi-language Support**: Global document processing
- **Scalable Search**: Handles millions of documents
- **Custom Ranking**: Configurable search ranking algorithms

### **6. File Storage (Private S3)**
```python
# S3 file management implementation
import boto3
from botocore.exceptions import ClientError
from typing import Optional, BinaryIO
import uuid

class S3FileManager:
    def __init__(self, endpoint_url: str, bucket_name: str, access_key: str, secret_key: str):
        self.s3_client = boto3.client(
            's3',
            endpoint_url=endpoint_url,
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key
        )
        self.bucket_name = bucket_name
    
    def upload_file(self, file_data: bytes, user_id: str, filename: str) -> str:
        """Upload file to private S3 with encryption"""
        file_id = str(uuid.uuid4())
        s3_key = f"users/{user_id}/files/{file_id}/{filename}"
        
        try:
            self.s3_client.put_object(
                Bucket=self.bucket_name,
                Key=s3_key,
                Body=file_data,
                ServerSideEncryption='AES256',
                Metadata={
                    'user_id': user_id,
                    'original_filename': filename,
                    'upload_timestamp': datetime.utcnow().isoformat()
                }
            )
            return s3_key
        except ClientError as e:
            raise Exception(f"Failed to upload file: {e}")
    
    def download_file(self, s3_key: str) -> bytes:
        """Download file from S3"""
        try:
            response = self.s3_client.get_object(Bucket=self.bucket_name, Key=s3_key)
            return response['Body'].read()
        except ClientError as e:
            raise Exception(f"Failed to download file: {e}")
    
    def delete_file(self, s3_key: str) -> bool:
        """Delete file from S3"""
        try:
            self.s3_client.delete_object(Bucket=self.bucket_name, Key=s3_key)
            return True
        except ClientError as e:
            raise Exception(f"Failed to delete file: {e}")
    
    def generate_presigned_url(self, s3_key: str, expiration: int = 3600) -> str:
        """Generate presigned URL for secure file access"""
        try:
            return self.s3_client.generate_presigned_url(
                'get_object',
                Params={'Bucket': self.bucket_name, 'Key': s3_key},
                ExpiresIn=expiration
            )
        except ClientError as e:
            raise Exception(f"Failed to generate presigned URL: {e}")
```

**S3 Configuration:**
- **Private Buckets**: Isolated from public internet
- **Encryption**: AES-256 server-side encryption
- **Access Control**: IAM-based permissions
- **Versioning**: File version management
- **Lifecycle Policies**: Automated data retention
- **Cross-Region Replication**: Disaster recovery

---

## 🔄 **Background Processing (Celery Workers)**

### **Worker Architecture**
```python
# Celery worker implementation
from celery import Celery
from celery.signals import worker_ready, worker_shutdown
from onyx.tasks.document_processing import process_document
from onyx.tasks.embedding_generation import generate_embeddings
from onyx.tasks.cleanup import cleanup_expired_sessions

# Celery app configuration
celery_app = Celery(
    'onyx-workers',
    broker='redis://redis.onyx-infra.svc.cluster.local:6379/0',
    backend='redis://redis.onyx-infra.svc.cluster.local:6379/0'
)

# Worker configuration
celery_app.conf.update(
    task_serializer='json',
    accept_content=['json'],
    result_serializer='json',
    timezone='UTC',
    enable_utc=True,
    task_track_started=True,
    task_time_limit=300,  # 5 minutes
    task_soft_time_limit=240,  # 4 minutes
    worker_prefetch_multiplier=1,
    worker_max_tasks_per_child=1000
)

@celery_app.task(bind=True, name='process_document')
def process_document_task(self, file_id: str, user_id: str):
    """Process uploaded document and generate embeddings"""
    try:
        # Download file from S3
        file_data = s3_manager.download_file(file_id)
        
        # Extract text content
        text_content = extract_text_from_file(file_data)
        
        # Generate embeddings
        embeddings = generate_embeddings(text_content)
        
        # Store in Vespa
        store_document_in_vespa(file_id, user_id, text_content, embeddings)
        
        # Update database
        update_document_status(file_id, 'processed')
        
        return {'status': 'success', 'file_id': file_id}
    except Exception as exc:
        # Retry logic
        raise self.retry(exc=exc, countdown=60, max_retries=3)
```

### **Specialized Worker Types**

#### **1. Primary Worker**
```python
# Primary worker for general tasks
@celery_app.task(name='primary_worker_task')
def primary_worker_task(task_type: str, data: dict):
    """Handle general background tasks"""
    if task_type == 'user_cleanup':
        cleanup_inactive_users()
    elif task_type == 'session_cleanup':
        cleanup_expired_sessions()
    elif task_type == 'health_check':
        perform_health_checks()
```

#### **2. Document Processing Worker**
```python
# Document processing worker
@celery_app.task(name='doc_processing_task', bind=True)
def doc_processing_task(self, file_id: str, user_id: str, file_type: str):
    """Process documents and generate embeddings"""
    try:
        # File processing pipeline
        document = download_and_process_file(file_id, file_type)
        
        # Generate embeddings using model server
        embeddings = call_model_server(document.content)
        
        # Index in Vespa
        index_document_in_vespa(document, embeddings, user_id)
        
        # Update processing status
        update_processing_status(file_id, 'completed')
        
    except Exception as exc:
        update_processing_status(file_id, 'failed')
        raise self.retry(exc=exc, countdown=60, max_retries=3)
```

#### **3. Knowledge Graph Worker**
```python
# Knowledge graph processing worker
@celery_app.task(name='kg_processing_task')
def kg_processing_task(document_id: str, content: str):
    """Process document for knowledge graph extraction"""
    try:
        # Extract entities and relationships
        entities = extract_entities(content)
        relationships = extract_relationships(content, entities)
        
        # Update knowledge graph
        update_knowledge_graph(document_id, entities, relationships)
        
        # Generate graph embeddings
        graph_embeddings = generate_graph_embeddings(entities, relationships)
        
        # Store in graph database
        store_graph_data(document_id, graph_embeddings)
        
    except Exception as exc:
        logger.error(f"KG processing failed for document {document_id}: {exc}")
```

---

## 🔐 **Security Implementation Details**

### **1. Authentication & Authorization**
```python
# JWT authentication implementation
import jwt
from datetime import datetime, timedelta
from fastapi import HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

class JWTAuthHandler:
    def __init__(self, secret_key: str, algorithm: str = "HS256"):
        self.secret_key = secret_key
        self.algorithm = algorithm
        self.security = HTTPBearer()
    
    def create_access_token(self, user_id: str, organization_id: str) -> str:
        """Create JWT access token"""
        payload = {
            'user_id': user_id,
            'organization_id': organization_id,
            'exp': datetime.utcnow() + timedelta(hours=24),
            'iat': datetime.utcnow(),
            'type': 'access'
        }
        return jwt.encode(payload, self.secret_key, algorithm=self.algorithm)
    
    def verify_token(self, credentials: HTTPAuthorizationCredentials = Depends(HTTPBearer())):
        """Verify JWT token and return user info"""
        try:
            payload = jwt.decode(
                credentials.credentials, 
                self.secret_key, 
                algorithms=[self.algorithm]
            )
            user_id = payload.get('user_id')
            if user_id is None:
                raise HTTPException(status_code=401, detail="Invalid token")
            return {'user_id': user_id, 'organization_id': payload.get('organization_id')}
        except jwt.ExpiredSignatureError:
            raise HTTPException(status_code=401, detail="Token expired")
        except jwt.JWTError:
            raise HTTPException(status_code=401, detail="Invalid token")
```

### **2. Data Isolation Implementation**
```python
# Data isolation middleware
from functools import wraps
from sqlalchemy.orm import Session

def require_user_context(f):
    """Decorator to ensure user context is available"""
    @wraps(f)
    async def decorated_function(*args, **kwargs):
        # Extract user context from JWT token
        user_context = get_current_user_context()
        
        # Add user context to database session
        db_session = get_db_session()
        db_session.execute(text("SET LOCAL row_security.user_id = :user_id"), 
                          {"user_id": user_context['user_id']})
        
        return await f(*args, **kwargs)
    return decorated_function

# Usage in API endpoints
@app.get("/api/documents")
@require_user_context
async def get_documents(db: Session = Depends(get_db)):
    """Get user's documents with automatic isolation"""
    # RLS automatically filters by user_id
    return db.query(Document).all()
```

### **3. File Access Control**
```python
# File access control implementation
class FileAccessController:
    def __init__(self, db_session: Session):
        self.db = db_session
    
    def can_access_file(self, user_id: str, file_id: str) -> bool:
        """Check if user can access specific file"""
        file_record = self.db.query(UserFile).filter(
            UserFile.id == file_id,
            UserFile.user_id == user_id
        ).first()
        return file_record is not None
    
    def get_file_s3_key(self, file_id: str, user_id: str) -> Optional[str]:
        """Get S3 key for file if user has access"""
        if self.can_access_file(user_id, file_id):
            file_record = self.db.query(UserFile).filter(
                UserFile.id == file_id
            ).first()
            return file_record.s3_key
        return None
```

---

## 📊 **Performance Optimization**

### **1. Database Optimization**
```sql
-- Optimized indexes for performance
CREATE INDEX CONCURRENTLY idx_chat_sessions_user_id ON chat_sessions(user_id);
CREATE INDEX CONCURRENTLY idx_chat_sessions_created_at ON chat_sessions(created_at DESC);
CREATE INDEX CONCURRENTLY idx_documents_user_id ON documents(user_id);
CREATE INDEX CONCURRENTLY idx_documents_organization_id ON documents(organization_id);

-- Partial indexes for active sessions
CREATE INDEX CONCURRENTLY idx_active_sessions ON chat_sessions(user_id) 
WHERE status = 'active';

-- Composite indexes for complex queries
CREATE INDEX CONCURRENTLY idx_user_org_created ON chat_sessions(user_id, organization_id, created_at DESC);
```

### **2. Caching Strategy**
```python
# Redis caching implementation
import redis
from functools import wraps
import json

class CacheManager:
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client
        self.default_ttl = 3600  # 1 hour
    
    def cache_result(self, ttl: int = None):
        """Decorator to cache function results"""
        def decorator(func):
            @wraps(func)
            async def wrapper(*args, **kwargs):
                # Generate cache key
                cache_key = f"{func.__name__}:{hash(str(args) + str(kwargs))}"
                
                # Try to get from cache
                cached_result = self.redis.get(cache_key)
                if cached_result:
                    return json.loads(cached_result)
                
                # Execute function and cache result
                result = await func(*args, **kwargs)
                self.redis.setex(
                    cache_key, 
                    ttl or self.default_ttl, 
                    json.dumps(result, default=str)
                )
                return result
            return wrapper
        return decorator

# Usage example
@cache_manager.cache_result(ttl=1800)  # 30 minutes
async def get_user_documents(user_id: str) -> List[Document]:
    """Get user documents with caching"""
    return db.query(Document).filter(Document.user_id == user_id).all()
```

### **3. Connection Pooling**
```python
# Database connection pooling
from sqlalchemy import create_engine
from sqlalchemy.pool import QueuePool

# PostgreSQL connection with pooling
engine = create_engine(
    "postgresql://user:password@postgresql.onyx-infra.svc.cluster.local:5432/onyx",
    poolclass=QueuePool,
    pool_size=20,          # Number of connections to maintain
    max_overflow=30,       # Additional connections when needed
    pool_pre_ping=True,    # Verify connections before use
    pool_recycle=3600,     # Recycle connections every hour
    echo=False
)

# Redis connection pooling
redis_pool = redis.ConnectionPool(
    host='redis.onyx-infra.svc.cluster.local',
    port=6379,
    db=0,
    max_connections=50,
    retry_on_timeout=True
)
```

---

## 🚀 **Deployment & Scaling**

### **1. Kubernetes Resource Management**
```yaml
# Resource specifications for production
apiVersion: apps/v1
kind: Deployment
metadata:
  name: onyx-api-server
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: api-server
        image: onyx/api-server:latest
        resources:
          requests:
            memory: "2Gi"
            cpu: "1000m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
        env:
        - name: DATABASE_URL
          value: "postgresql://user:pass@postgresql.onyx-infra.svc.cluster.local:5432/onyx"
        - name: REDIS_URL
          value: "redis://redis.onyx-infra.svc.cluster.local:6379/0"
        - name: S3_ENDPOINT
          value: "https://your-private-s3.company.com"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

### **2. Horizontal Pod Autoscaling**
```yaml
# HPA configuration
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: onyx-api-server-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: onyx-api-server
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

---

## 📈 **Monitoring & Observability**

### **1. Application Metrics**
```python
# Prometheus metrics implementation
from prometheus_client import Counter, Histogram, Gauge, start_http_server
import time

# Define metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_DURATION = Histogram('http_request_duration_seconds', 'HTTP request duration')
ACTIVE_SESSIONS = Gauge('active_sessions_total', 'Number of active user sessions')
DOCUMENTS_PROCESSED = Counter('documents_processed_total', 'Total documents processed')

# Middleware to collect metrics
@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start_time = time.time()
    
    response = await call_next(request)
    
    # Record metrics
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()
    
    REQUEST_DURATION.observe(time.time() - start_time)
    
    return response
```

### **2. Health Checks**
```python
# Comprehensive health check implementation
@app.get("/health")
async def health_check():
    """Comprehensive health check endpoint"""
    health_status = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "services": {}
    }
    
    # Check database connectivity
    try:
        db.execute(text("SELECT 1"))
        health_status["services"]["database"] = "healthy"
    except Exception as e:
        health_status["services"]["database"] = f"unhealthy: {str(e)}"
        health_status["status"] = "unhealthy"
    
    # Check Redis connectivity
    try:
        redis_client.ping()
        health_status["services"]["redis"] = "healthy"
    except Exception as e:
        health_status["services"]["redis"] = f"unhealthy: {str(e)}"
        health_status["status"] = "unhealthy"
    
    # Check S3 connectivity
    try:
        s3_client.head_bucket(Bucket=bucket_name)
        health_status["services"]["s3"] = "healthy"
    except Exception as e:
        health_status["services"]["s3"] = f"unhealthy: {str(e)}"
        health_status["status"] = "unhealthy"
    
    # Check Vespa connectivity
    try:
        vespa_client.get_application_status()
        health_status["services"]["vespa"] = "healthy"
    except Exception as e:
        health_status["services"]["vespa"] = f"unhealthy: {str(e)}"
        health_status["status"] = "unhealthy"
    
    return health_status
```

---

## 🎯 **Conclusion**

Onyx's technical architecture represents a modern, enterprise-grade solution built on proven technologies and best practices. The system's microservices architecture, comprehensive security model, and robust data isolation mechanisms make it an ideal choice for organizations requiring secure, scalable AI-powered document management.

**Key Technical Advantages:**
- **Scalable Architecture**: Microservices with independent scaling
- **Security First**: Multi-layer security with data isolation
- **Performance Optimized**: Caching, connection pooling, and efficient queries
- **Cloud Native**: Kubernetes/OpenShift ready with auto-scaling
- **Observable**: Comprehensive monitoring and health checks
- **Maintainable**: Clean code architecture with proper separation of concerns

This technical foundation ensures Onyx can handle enterprise workloads while maintaining security, performance, and reliability at scale.
