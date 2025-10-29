# Onyx Enterprise Security & Data Management
## Comprehensive Technical Documentation

---

## 🛡️ **Executive Summary**

Onyx is a next-generation enterprise AI platform designed with security, scalability, and data isolation at its core. Built on modern microservices architecture and deployed on Kubernetes/OpenShift, Onyx provides enterprise-grade security features, robust data separation, and comprehensive file management capabilities that make it the ideal choice for organizations requiring secure, scalable AI-powered document processing and knowledge management.

---

## 🔐 **Security Architecture**

### **Multi-Layer Security Model**

Onyx implements a comprehensive security architecture that protects data at every layer:

#### **1. Network Security**
- **Network Policies**: Granular network segmentation controlling pod-to-pod communication
- **TLS Encryption**: All inter-service communication encrypted in transit
- **Private S3 Storage**: File storage isolated in private S3 buckets with encryption at rest
- **Service Mesh Ready**: Compatible with Istio/Linkerd for advanced traffic management

#### **2. Authentication & Authorization**
- **JWT-Based Sessions**: Secure, stateless authentication with configurable expiration
- **Role-Based Access Control (RBAC)**: Granular permissions for different user types
- **Company-Only Access**: Domain-based and invitation-only user registration
- **Session Management**: Secure session handling with Redis-based storage

#### **3. Data Protection**
- **Encryption at Rest**: All data encrypted using industry-standard algorithms
- **Encryption in Transit**: TLS 1.3 for all API communications
- **Data Isolation**: Complete separation between organizations and users
- **Audit Logging**: Comprehensive logging of all data access and modifications

### **Security Features in Detail**

#### **🔒 Company-Only Authentication**
```yaml
# Configurable company restrictions
ENABLE_EMAIL_INVITES: "true"           # Invitation-only registration
VALID_EMAIL_DOMAINS: "yourcompany.com" # Domain whitelist
```

**Benefits:**
- Prevents unauthorized access from external domains
- Ensures only company employees can register
- Supports multiple domain validation
- Integrates with existing corporate identity systems

#### **🛡️ Session Security**
- **Secure Session Storage**: Sessions stored in Redis with encryption
- **Automatic Expiration**: Configurable session timeouts
- **Concurrent Session Management**: Control over multiple active sessions
- **Session Invalidation**: Immediate logout across all devices

---

## 📊 **Data Architecture & Storage**

### **Multi-Tier Data Storage Strategy**

Onyx employs a sophisticated multi-tier storage architecture optimized for performance, security, and scalability:

#### **1. PostgreSQL - Primary Database**
```sql
-- User data isolation example
CREATE TABLE chat_sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Row Level Security (RLS) ensures data isolation
ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_isolation ON chat_sessions 
    FOR ALL TO authenticated 
    USING (user_id = current_user_id());
```

**Key Features:**
- **Row Level Security (RLS)**: Database-level data isolation
- **Foreign Key Constraints**: Cascading deletes ensure data integrity
- **ACID Compliance**: Full transaction support for data consistency
- **Backup & Recovery**: Automated backup strategies with point-in-time recovery

#### **2. Redis - High-Performance Cache & Session Store**
```yaml
# Redis configuration for enterprise use
REDIS_HOST: "redis.onyx-infra.svc.cluster.local"
REDIS_PORT: "6379"
REDIS_PASSWORD: "encrypted-password"
REDIS_DB: "0"  # Separate databases for different data types
```

**Use Cases:**
- **Session Management**: Secure user session storage
- **Task Queue**: Celery worker coordination
- **Caching**: High-frequency data caching
- **Real-time Features**: WebSocket connection management

#### **3. Vespa - Vector Search Engine**
```yaml
# Vespa configuration for document search
VESPA_HOST: "vespa.onyx-infra.svc.cluster.local"
VESPA_PORT: "8080"
VESPA_APPLICATION: "onyx-search"
```

**Capabilities:**
- **Semantic Search**: AI-powered document search
- **Real-time Indexing**: Instant search capability
- **Scalable Search**: Handles millions of documents
- **Multi-language Support**: Global document processing

#### **4. Private S3 - File Storage**
```yaml
# S3 configuration for secure file storage
S3_ENDPOINT: "https://your-private-s3.company.com"
S3_BUCKET: "onyx-documents"
S3_ACCESS_KEY: "encrypted-access-key"
S3_SECRET_KEY: "encrypted-secret-key"
S3_REGION: "us-east-1"
```

**Security Features:**
- **Private S3 Buckets**: Isolated from public internet
- **Encryption at Rest**: AES-256 encryption
- **Access Control**: IAM-based permissions
- **Versioning**: File version management
- **Lifecycle Policies**: Automated data retention

---

## 👥 **User Data Separation & Isolation**

### **Multi-Tenant Architecture**

Onyx implements a sophisticated multi-tenant architecture ensuring complete data isolation:

#### **1. User-Level Isolation**
```python
# Example: User data filtering
def get_user_chat_sessions(user_id: UUID):
    return db.query(ChatSession).filter(
        ChatSession.user_id == user_id,
        ChatSession.organization_id == get_user_organization(user_id)
    ).all()
```

**Isolation Mechanisms:**
- **User ID Foreign Keys**: All data linked to specific users
- **Database Queries**: Always filtered by user context
- **API Endpoints**: User context automatically injected
- **Cascading Deletes**: User deletion removes all associated data

#### **2. Organization-Level Isolation**
```python
# Organization-based data separation
class Organization:
    id: UUID
    name: str
    domain: str
    settings: Dict
    
    def get_users(self):
        return User.query.filter(User.organization_id == self.id)
```

**Features:**
- **Domain-Based Separation**: Users isolated by company domain
- **Organization Settings**: Customizable per-organization configurations
- **Billing Isolation**: Separate usage tracking per organization
- **Admin Controls**: Organization-level administrative functions

#### **3. Session Management**
```python
# Secure session handling
class SessionManager:
    def create_session(self, user_id: UUID, organization_id: UUID):
        session_data = {
            'user_id': str(user_id),
            'organization_id': str(organization_id),
            'created_at': datetime.utcnow(),
            'expires_at': datetime.utcnow() + timedelta(hours=24)
        }
        return self.redis.setex(
            f"session:{session_id}", 
            86400,  # 24 hours
            json.dumps(session_data)
        )
```

**Session Features:**
- **Secure Token Generation**: Cryptographically secure session IDs
- **Automatic Expiration**: Configurable session timeouts
- **Multi-Device Support**: Sessions across different devices
- **Session Invalidation**: Immediate logout capability

---

## 📁 **Advanced File Management System**

### **Enterprise-Grade File Storage**

Onyx provides a comprehensive file management system designed for enterprise use:

#### **1. File Upload & Processing**
```yaml
# File processing configuration
MAX_FILE_SIZE: "100MB"           # Configurable file size limits
SUPPORTED_FORMATS: "pdf,docx,txt,md,html"  # Multiple format support
PROCESSING_QUEUE: "celery-workers"  # Asynchronous processing
```

**Supported Features:**
- **Multiple Formats**: PDF, DOCX, TXT, Markdown, HTML, and more
- **Large File Support**: Up to 100MB per file (configurable)
- **Asynchronous Processing**: Non-blocking file uploads
- **Progress Tracking**: Real-time upload progress
- **Error Handling**: Comprehensive error reporting

#### **2. File Storage Architecture**
```python
# File storage implementation
class FileManager:
    def upload_file(self, file_data: bytes, user_id: UUID, filename: str):
        # Generate unique file ID
        file_id = str(uuid4())
        
        # Upload to private S3
        s3_key = f"users/{user_id}/files/{file_id}/{filename}"
        self.s3_client.put_object(
            Bucket=self.bucket_name,
            Key=s3_key,
            Body=file_data,
            ServerSideEncryption='AES256'
        )
        
        # Store metadata in PostgreSQL
        file_record = UserFile(
            id=file_id,
            user_id=user_id,
            filename=filename,
            s3_key=s3_key,
            size=len(file_data),
            uploaded_at=datetime.utcnow()
        )
        db.session.add(file_record)
        db.session.commit()
```

**Storage Benefits:**
- **Private S3 Storage**: Files stored in your private S3 buckets
- **Encryption**: All files encrypted at rest
- **Metadata Tracking**: Complete file information in database
- **Access Control**: User-based file access permissions
- **Versioning**: File version management capabilities

#### **3. File Deletion & Management**
```python
# Secure file deletion
def delete_user_file(file_id: UUID, user_id: UUID):
    # Verify ownership
    file_record = UserFile.query.filter(
        UserFile.id == file_id,
        UserFile.user_id == user_id
    ).first()
    
    if file_record:
        # Delete from S3
        s3_client.delete_object(
            Bucket=bucket_name,
            Key=file_record.s3_key
        )
        
        # Remove from database
        db.session.delete(file_record)
        db.session.commit()
        
        # Clean up related data
        cleanup_file_references(file_id)
```

**Deletion Features:**
- **Secure Deletion**: Files permanently removed from S3
- **Cascading Cleanup**: Related data automatically cleaned up
- **Audit Trail**: Deletion events logged for compliance
- **Recovery Options**: Configurable soft delete for critical files

#### **4. File Access & Permissions**
```python
# File access control
def get_user_files(user_id: UUID, project_id: UUID = None):
    query = UserFile.query.filter(UserFile.user_id == user_id)
    
    if project_id:
        query = query.join(ProjectFile).filter(
            ProjectFile.project_id == project_id
        )
    
    return query.order_by(UserFile.uploaded_at.desc()).all()
```

**Access Control:**
- **User-Specific Access**: Users only see their own files
- **Project-Based Organization**: Files organized by projects
- **Role-Based Permissions**: Different access levels for different users
- **Sharing Controls**: Secure file sharing between users

---

## 🚀 **Performance & Scalability**

### **Horizontal Scaling Architecture**

Onyx is designed for enterprise-scale deployments:

#### **1. Microservices Architecture**
- **Independent Scaling**: Each service scales independently
- **Load Distribution**: NGINX load balancing
- **Resource Optimization**: CPU/memory limits per service
- **Health Monitoring**: Comprehensive health checks

#### **2. Background Processing**
```yaml
# Celery worker configuration
CELERY_WORKERS:
  - Primary: 2 instances    # General tasks
  - Docfetching: 3 instances  # Document retrieval
  - Docprocessing: 4 instances # Document processing
  - Light: 2 instances      # Quick tasks
  - Heavy: 1 instance       # Resource-intensive tasks
  - KG Processing: 1 instance # Knowledge graph tasks
  - Monitoring: 1 instance  # System monitoring
  - Beat: 1 instance        # Scheduled tasks
```

**Benefits:**
- **Asynchronous Processing**: Non-blocking operations
- **Specialized Workers**: Optimized for specific task types
- **Queue Management**: Intelligent task distribution
- **Fault Tolerance**: Worker failure recovery

#### **3. Caching Strategy**
- **Redis Caching**: High-frequency data caching
- **Query Optimization**: Database query optimization
- **CDN Integration**: Static asset delivery
- **Session Caching**: Fast session retrieval

---

## 📈 **Enterprise Features**

### **1. Monitoring & Observability**
- **Comprehensive Logging**: All operations logged
- **Metrics Collection**: Performance and usage metrics
- **Health Dashboards**: Real-time system status
- **Alerting**: Proactive issue detection

### **2. Compliance & Governance**
- **Data Retention Policies**: Configurable data lifecycle
- **Audit Logging**: Complete audit trail
- **GDPR Compliance**: Data protection compliance
- **SOC 2 Ready**: Security framework compliance

### **3. Integration Capabilities**
- **REST APIs**: Comprehensive API coverage
- **Webhook Support**: Real-time event notifications
- **SSO Integration**: Single sign-on support
- **LDAP/Active Directory**: Enterprise directory integration

---

## 🎯 **Why Choose Onyx?**

### **For Enterprise IT Teams:**
- **Security First**: Multi-layer security architecture
- **Scalable**: Handles 100-500+ users with ease
- **Compliant**: Built for enterprise compliance requirements
- **Maintainable**: Modern microservices architecture

### **For Business Users:**
- **Intuitive Interface**: User-friendly document management
- **Powerful Search**: AI-powered semantic search
- **Collaboration**: Team-based document sharing
- **Productivity**: Streamlined document workflows

### **For Security Teams:**
- **Data Isolation**: Complete user and organization separation
- **Encryption**: End-to-end encryption
- **Access Control**: Granular permission management
- **Audit Trail**: Comprehensive activity logging

---

## 🔧 **Deployment Architecture**

### **Kubernetes/OpenShift Ready**
```yaml
# Example deployment configuration
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
```

**Deployment Benefits:**
- **High Availability**: Multi-replica deployments
- **Auto-scaling**: Automatic scaling based on load
- **Rolling Updates**: Zero-downtime deployments
- **Resource Management**: Efficient resource utilization

---

## 📋 **Getting Started**

### **Quick Deployment**
1. **Configure Environment**: Set up your private S3 and database
2. **Deploy Services**: Use provided Kubernetes manifests
3. **Configure Security**: Set up authentication and access controls
4. **Import Data**: Upload and process your documents
5. **Start Using**: Begin with AI-powered document search

### **Support & Documentation**
- **Comprehensive Docs**: Detailed technical documentation
- **API Reference**: Complete API documentation
- **Troubleshooting**: Step-by-step problem resolution
- **Community Support**: Active community and support channels

---

## 🎉 **Conclusion**

Onyx represents the future of enterprise AI-powered document management. With its robust security architecture, comprehensive data isolation, and advanced file management capabilities, Onyx provides everything your organization needs to securely manage, search, and collaborate on documents at scale.

**Ready to transform your document management?** Deploy Onyx today and experience the power of secure, scalable, AI-driven document processing.

---

*For technical support, deployment assistance, or custom integrations, contact our team or visit our documentation portal.*
