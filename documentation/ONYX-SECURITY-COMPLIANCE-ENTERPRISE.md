# Onyx Security & Compliance Framework
## Enterprise-Grade Security, Privacy, and Regulatory Compliance

---

## 🛡️ **Executive Security Summary**

Onyx is architected with security as a fundamental design principle, implementing defense-in-depth strategies across all layers of the application stack. Our comprehensive security framework ensures data protection, regulatory compliance, and enterprise-grade security controls that meet the most stringent organizational requirements.

---

## 🔐 **Security Architecture Overview**

### **Multi-Layer Defense Strategy**

Onyx implements a comprehensive security architecture with multiple layers of protection:

```
┌─────────────────────────────────────────────────────────────┐
│                    SECURITY LAYERS                         │
├─────────────────────────────────────────────────────────────┤
│  Layer 7: Application Security (Authentication, RBAC)     │
├─────────────────────────────────────────────────────────────┤
│  Layer 6: Data Security (Encryption, Data Isolation)      │
├─────────────────────────────────────────────────────────────┤
│  Layer 5: Session Security (JWT, Session Management)      │
├─────────────────────────────────────────────────────────────┤
│  Layer 4: Transport Security (TLS 1.3, Certificate Mgmt)  │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: Network Security (Network Policies, Firewalls)  │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: Infrastructure Security (K8s Security Context)  │
├─────────────────────────────────────────────────────────────┤
│  Layer 1: Physical Security (Private S3, Secure Storage)  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔒 **Authentication & Authorization**

### **1. Multi-Factor Authentication (MFA)**
```python
# MFA implementation
class MultiFactorAuth:
    def __init__(self, db_session: Session, redis_client: Redis):
        self.db = db_session
        self.redis = redis_client
        self.totp_secret_length = 32
    
    def generate_totp_secret(self, user_id: str) -> str:
        """Generate TOTP secret for user"""
        secret = pyotp.random_base32()
        
        # Store encrypted secret
        encrypted_secret = self.encrypt_secret(secret)
        
        user_mfa = UserMFA(
            user_id=user_id,
            totp_secret=encrypted_secret,
            enabled=False,
            created_at=datetime.utcnow()
        )
        
        self.db.add(user_mfa)
        self.db.commit()
        
        return secret
    
    def verify_totp_code(self, user_id: str, code: str) -> bool:
        """Verify TOTP code"""
        user_mfa = self.db.query(UserMFA).filter(
            UserMFA.user_id == user_id,
            UserMFA.enabled == True
        ).first()
        
        if not user_mfa:
            return False
        
        secret = self.decrypt_secret(user_mfa.totp_secret)
        totp = pyotp.TOTP(secret)
        
        return totp.verify(code, valid_window=1)
    
    def enable_mfa(self, user_id: str, totp_code: str) -> bool:
        """Enable MFA for user after verification"""
        if self.verify_totp_code(user_id, totp_code):
            user_mfa = self.db.query(UserMFA).filter(
                UserMFA.user_id == user_id
            ).first()
            
            if user_mfa:
                user_mfa.enabled = True
                user_mfa.enabled_at = datetime.utcnow()
                self.db.commit()
                return True
        
        return False
```

### **2. Role-Based Access Control (RBAC)**
```python
# Comprehensive RBAC implementation
class RoleBasedAccessControl:
    def __init__(self, db_session: Session):
        self.db = db_session
    
    def create_role(self, name: str, permissions: List[str], organization_id: str) -> str:
        """Create a new role with specific permissions"""
        role = Role(
            id=str(uuid.uuid4()),
            name=name,
            organization_id=organization_id,
            permissions=permissions,
            created_at=datetime.utcnow()
        )
        
        self.db.add(role)
        self.db.commit()
        
        return role.id
    
    def assign_role_to_user(self, user_id: str, role_id: str) -> bool:
        """Assign role to user"""
        # Verify role exists and user belongs to same organization
        role = self.db.query(Role).filter(Role.id == role_id).first()
        user = self.db.query(User).filter(User.id == user_id).first()
        
        if not role or not user or role.organization_id != user.organization_id:
            return False
        
        # Check if user already has this role
        existing_assignment = self.db.query(UserRole).filter(
            UserRole.user_id == user_id,
            UserRole.role_id == role_id
        ).first()
        
        if existing_assignment:
            return True
        
        # Create role assignment
        user_role = UserRole(
            user_id=user_id,
            role_id=role_id,
            assigned_at=datetime.utcnow()
        )
        
        self.db.add(user_role)
        self.db.commit()
        
        return True
    
    def check_permission(self, user_id: str, permission: str) -> bool:
        """Check if user has specific permission"""
        user_roles = self.db.query(Role).join(UserRole).filter(
            UserRole.user_id == user_id
        ).all()
        
        for role in user_roles:
            if permission in role.permissions:
                return True
        
        return False
    
    def get_user_permissions(self, user_id: str) -> List[str]:
        """Get all permissions for user"""
        user_roles = self.db.query(Role).join(UserRole).filter(
            UserRole.user_id == user_id
        ).all()
        
        permissions = set()
        for role in user_roles:
            permissions.update(role.permissions)
        
        return list(permissions)

# Permission decorator
def require_permission(permission: str):
    """Decorator to require specific permission"""
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # Extract user from request context
            user_id = get_current_user_id()
            
            if not rbac.check_permission(user_id, permission):
                raise HTTPException(
                    status_code=403, 
                    detail=f"Permission '{permission}' required"
                )
            
            return await func(*args, **kwargs)
        return wrapper
    return decorator

# Usage example
@app.get("/api/admin/users")
@require_permission("admin.users.read")
async def get_all_users():
    """Get all users - requires admin.users.read permission"""
    return get_all_users_from_db()
```

### **3. Session Security**
```python
# Advanced session security implementation
class SecureSessionManager:
    def __init__(self, redis_client: Redis, secret_key: str):
        self.redis = redis_client
        self.secret_key = secret_key
        self.session_timeout = 86400  # 24 hours
        self.max_concurrent_sessions = 5
    
    def create_secure_session(
        self, 
        user_id: str, 
        organization_id: str, 
        ip_address: str,
        user_agent: str
    ) -> str:
        """Create secure session with comprehensive tracking"""
        session_id = self._generate_secure_session_id()
        
        # Check concurrent session limit
        active_sessions = self._get_user_active_sessions(user_id)
        if len(active_sessions) >= self.max_concurrent_sessions:
            # Remove oldest session
            oldest_session = min(active_sessions, key=lambda x: x['created_at'])
            self._invalidate_session(oldest_session['session_id'])
        
        session_data = {
            'session_id': session_id,
            'user_id': user_id,
            'organization_id': organization_id,
            'ip_address': ip_address,
            'user_agent': user_agent,
            'created_at': datetime.utcnow().isoformat(),
            'last_activity': datetime.utcnow().isoformat(),
            'expires_at': (datetime.utcnow() + timedelta(seconds=self.session_timeout)).isoformat(),
            'is_active': True
        }
        
        # Store session with encryption
        encrypted_session = self._encrypt_session_data(session_data)
        self.redis.setex(
            f"secure_session:{session_id}",
            self.session_timeout,
            encrypted_session
        )
        
        # Track session in user's session list
        self.redis.sadd(f"user_sessions:{user_id}", session_id)
        
        return session_id
    
    def validate_session(self, session_id: str, ip_address: str) -> Optional[Dict]:
        """Validate session with IP and activity checks"""
        session_data = self._get_session_data(session_id)
        
        if not session_data:
            return None
        
        # Check IP address (optional - can be disabled for mobile users)
        if session_data.get('ip_address') != ip_address:
            # Log suspicious activity
            self._log_suspicious_activity(session_id, 'ip_mismatch', ip_address)
            # Optionally invalidate session
            # self._invalidate_session(session_id)
            # return None
        
        # Update last activity
        session_data['last_activity'] = datetime.utcnow().isoformat()
        self._update_session_data(session_id, session_data)
        
        return session_data
    
    def invalidate_session(self, session_id: str) -> bool:
        """Invalidate specific session"""
        session_data = self._get_session_data(session_id)
        
        if session_data:
            user_id = session_data.get('user_id')
            if user_id:
                # Remove from user's session list
                self.redis.srem(f"user_sessions:{user_id}", session_id)
            
            # Remove session data
            self.redis.delete(f"secure_session:{session_id}")
            
            return True
        
        return False
    
    def invalidate_all_user_sessions(self, user_id: str) -> int:
        """Invalidate all sessions for a user (logout from all devices)"""
        user_sessions = self.redis.smembers(f"user_sessions:{user_id}")
        deleted_count = 0
        
        for session_id in user_sessions:
            if self.invalidate_session(session_id.decode()):
                deleted_count += 1
        
        return deleted_count
    
    def _generate_secure_session_id(self) -> str:
        """Generate cryptographically secure session ID"""
        return secrets.token_urlsafe(32)
    
    def _encrypt_session_data(self, session_data: Dict) -> str:
        """Encrypt session data"""
        json_data = json.dumps(session_data)
        f = Fernet(self.secret_key.encode())
        return f.encrypt(json_data.encode()).decode()
    
    def _decrypt_session_data(self, encrypted_data: str) -> Dict:
        """Decrypt session data"""
        f = Fernet(self.secret_key.encode())
        decrypted = f.decrypt(encrypted_data.encode())
        return json.loads(decrypted.decode())
```

---

## 🔐 **Data Encryption & Protection**

### **1. Encryption at Rest**
```python
# Comprehensive encryption implementation
class DataEncryption:
    def __init__(self, master_key: str):
        self.master_key = master_key.encode()
        self.cipher_suite = Fernet(self.master_key)
    
    def encrypt_sensitive_data(self, data: str) -> str:
        """Encrypt sensitive data for database storage"""
        if not data:
            return data
        
        encrypted_data = self.cipher_suite.encrypt(data.encode())
        return base64.b64encode(encrypted_data).decode()
    
    def decrypt_sensitive_data(self, encrypted_data: str) -> str:
        """Decrypt sensitive data from database"""
        if not encrypted_data:
            return encrypted_data
        
        try:
            decoded_data = base64.b64decode(encrypted_data.encode())
            decrypted_data = self.cipher_suite.decrypt(decoded_data)
            return decrypted_data.decode()
        except Exception as e:
            logger.error(f"Decryption failed: {e}")
            raise ValueError("Failed to decrypt data")
    
    def encrypt_file_content(self, file_content: bytes) -> bytes:
        """Encrypt file content for S3 storage"""
        return self.cipher_suite.encrypt(file_content)
    
    def decrypt_file_content(self, encrypted_content: bytes) -> bytes:
        """Decrypt file content from S3 storage"""
        return self.cipher_suite.decrypt(encrypted_content)

# Database model with encryption
class User(Base):
    __tablename__ = 'users'
    
    id = Column(UUID, primary_key=True, default=uuid.uuid4)
    email = Column(String(255), unique=True, nullable=False)
    encrypted_password = Column(Text, nullable=False)
    encrypted_first_name = Column(Text)  # Encrypted PII
    encrypted_last_name = Column(Text)   # Encrypted PII
    organization_id = Column(UUID, ForeignKey('organizations.id'))
    created_at = Column(DateTime, default=datetime.utcnow)
    
    def set_password(self, password: str):
        """Set encrypted password"""
        self.encrypted_password = encryption.encrypt_sensitive_data(password)
    
    def check_password(self, password: str) -> bool:
        """Check password against encrypted version"""
        stored_password = encryption.decrypt_sensitive_data(self.encrypted_password)
        return bcrypt.checkpw(password.encode(), stored_password.encode())
    
    @property
    def first_name(self) -> str:
        """Get decrypted first name"""
        return encryption.decrypt_sensitive_data(self.encrypted_first_name)
    
    @first_name.setter
    def first_name(self, value: str):
        """Set encrypted first name"""
        self.encrypted_first_name = encryption.encrypt_sensitive_data(value)
```

### **2. Encryption in Transit**
```python
# TLS configuration for all communications
class SecureTransport:
    def __init__(self):
        self.tls_version = "TLSv1.3"
        self.cipher_suites = [
            "TLS_AES_256_GCM_SHA384",
            "TLS_CHACHA20_POLY1305_SHA256",
            "TLS_AES_128_GCM_SHA256"
        ]
    
    def create_secure_context(self) -> ssl.SSLContext:
        """Create secure SSL context"""
        context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
        context.minimum_version = ssl.TLSVersion.TLSv1_3
        context.set_ciphers(':'.join(self.cipher_suites))
        context.check_hostname = True
        context.verify_mode = ssl.CERT_REQUIRED
        
        return context
    
    def configure_https_client(self):
        """Configure HTTPS client with security settings"""
        ssl_context = self.create_secure_context()
        
        # Configure HTTP client
        client = httpx.AsyncClient(
            verify=ssl_context,
            timeout=30.0,
            limits=httpx.Limits(
                max_keepalive_connections=20,
                max_connections=100
            )
        )
        
        return client

# FastAPI security configuration
app = FastAPI(
    title="Onyx API",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url="/api/redoc"
)

# Security headers middleware
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    
    # Security headers
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Content-Security-Policy"] = "default-src 'self'"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    
    return response
```

---

## 🏢 **Data Isolation & Multi-Tenancy**

### **1. Row Level Security (RLS)**
```sql
-- Enable RLS on all user data tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_files ENABLE ROW LEVEL SECURITY;

-- User isolation policies
CREATE POLICY user_isolation ON users
    FOR ALL TO authenticated
    USING (id = current_user_id());

CREATE POLICY chat_session_isolation ON chat_sessions
    FOR ALL TO authenticated
    USING (user_id = current_user_id());

CREATE POLICY document_isolation ON documents
    FOR ALL TO authenticated
    USING (user_id = current_user_id());

CREATE POLICY file_isolation ON user_files
    FOR ALL TO authenticated
    USING (user_id = current_user_id());

-- Organization isolation policies
CREATE POLICY organization_isolation ON organizations
    FOR ALL TO authenticated
    USING (id = current_user_organization_id());

-- Admin override policy (for system administrators)
CREATE POLICY admin_override ON users
    FOR ALL TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM user_roles ur
            JOIN roles r ON ur.role_id = r.id
            WHERE ur.user_id = current_user_id()
            AND 'admin.users.all' = ANY(r.permissions)
        )
    );
```

### **2. Application-Level Data Isolation**
```python
# Data isolation middleware
class DataIsolationMiddleware:
    def __init__(self, db_session_factory):
        self.db_session_factory = db_session_factory
    
    async def __call__(self, request: Request, call_next):
        # Extract user context from JWT
        user_context = self.extract_user_context(request)
        
        if user_context:
            # Set user context in database session
            db_session = self.db_session_factory()
            
            # Set RLS context
            db_session.execute(
                text("SET LOCAL row_security.user_id = :user_id"),
                {"user_id": user_context['user_id']}
            )
            db_session.execute(
                text("SET LOCAL row_security.organization_id = :org_id"),
                {"org_id": user_context['organization_id']}
            )
            
            # Store in request state
            request.state.db_session = db_session
            request.state.user_context = user_context
        
        response = await call_next(request)
        
        # Cleanup
        if hasattr(request.state, 'db_session'):
            request.state.db_session.close()
        
        return response
    
    def extract_user_context(self, request: Request) -> Optional[Dict]:
        """Extract user context from JWT token"""
        auth_header = request.headers.get('Authorization')
        if not auth_header or not auth_header.startswith('Bearer '):
            return None
        
        token = auth_header.split(' ')[1]
        try:
            payload = jwt.decode(token, SECRET_KEY, algorithms=['HS256'])
            return {
                'user_id': payload.get('user_id'),
                'organization_id': payload.get('organization_id')
            }
        except jwt.JWTError:
            return None

# Database query with automatic isolation
class IsolatedQuery:
    def __init__(self, db_session: Session, user_context: Dict):
        self.db = db_session
        self.user_id = user_context['user_id']
        self.organization_id = user_context['organization_id']
    
    def get_user_documents(self) -> Query:
        """Get user's documents with automatic isolation"""
        return self.db.query(Document).filter(
            Document.user_id == self.user_id
        )
    
    def get_organization_users(self) -> Query:
        """Get users in same organization"""
        return self.db.query(User).filter(
            User.organization_id == self.organization_id
        )
    
    def get_shared_files(self) -> Query:
        """Get files shared with user"""
        return self.db.query(UserFile).join(FileShare).filter(
            FileShare.shared_with_user_id == self.user_id
        )
```

---

## 📊 **Audit Logging & Compliance**

### **1. Comprehensive Audit System**
```python
# Enterprise audit logging system
class AuditLogger:
    def __init__(self, db_session: Session, redis_client: Redis):
        self.db = db_session
        self.redis = redis_client
    
    def log_audit_event(
        self,
        event_type: str,
        user_id: str,
        resource_type: str,
        resource_id: str,
        action: str,
        details: Dict = None,
        ip_address: str = None,
        user_agent: str = None
    ):
        """Log comprehensive audit event"""
        audit_event = AuditEvent(
            id=str(uuid.uuid4()),
            event_type=event_type,
            user_id=user_id,
            organization_id=self.get_user_organization(user_id),
            resource_type=resource_type,
            resource_id=resource_id,
            action=action,
            details=details or {},
            ip_address=ip_address,
            user_agent=user_agent,
            timestamp=datetime.utcnow(),
            severity=self._determine_severity(event_type, action)
        )
        
        self.db.add(audit_event)
        self.db.commit()
        
        # Also log to Redis for real-time monitoring
        self._log_to_redis(audit_event)
    
    def log_data_access(self, user_id: str, resource_type: str, resource_id: str, action: str):
        """Log data access events"""
        self.log_audit_event(
            event_type="data_access",
            user_id=user_id,
            resource_type=resource_type,
            resource_id=resource_id,
            action=action,
            details={"access_type": "read" if action == "view" else "write"}
        )
    
    def log_authentication_event(self, user_id: str, event_type: str, success: bool, details: Dict = None):
        """Log authentication events"""
        self.log_audit_event(
            event_type="authentication",
            user_id=user_id,
            resource_type="user_session",
            resource_id=user_id,
            action=event_type,
            details={
                "success": success,
                **(details or {})
            }
        )
    
    def log_security_event(self, event_type: str, severity: str, details: Dict, user_id: str = None):
        """Log security-related events"""
        self.log_audit_event(
            event_type="security",
            user_id=user_id or "system",
            resource_type="security",
            resource_id=str(uuid.uuid4()),
            action=event_type,
            details=details
        )
    
    def get_audit_trail(self, user_id: str = None, resource_type: str = None, limit: int = 100) -> List[AuditEvent]:
        """Get audit trail with filtering"""
        query = self.db.query(AuditEvent)
        
        if user_id:
            query = query.filter(AuditEvent.user_id == user_id)
        
        if resource_type:
            query = query.filter(AuditEvent.resource_type == resource_type)
        
        return query.order_by(AuditEvent.timestamp.desc()).limit(limit).all()
    
    def _determine_severity(self, event_type: str, action: str) -> str:
        """Determine event severity"""
        if event_type == "security":
            return "high"
        elif action in ["delete", "admin_action"]:
            return "medium"
        else:
            return "low"

# Audit decorator for automatic logging
def audit_log(event_type: str, resource_type: str, action: str):
    """Decorator to automatically log audit events"""
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            # Extract user context
            user_id = get_current_user_id()
            
            # Execute function
            result = await func(*args, **kwargs)
            
            # Log audit event
            audit_logger.log_audit_event(
                event_type=event_type,
                user_id=user_id,
                resource_type=resource_type,
                resource_id=str(result.get('id', 'unknown')),
                action=action
            )
            
            return result
        return wrapper
    return decorator

# Usage examples
@app.delete("/api/files/{file_id}")
@audit_log("data_access", "user_file", "delete")
async def delete_file(file_id: str):
    """Delete file with automatic audit logging"""
    return delete_file_from_storage(file_id)

@app.post("/api/admin/users")
@audit_log("admin_action", "user", "create")
async def create_user(user_data: UserCreate):
    """Create user with automatic audit logging"""
    return create_new_user(user_data)
```

### **2. Compliance Reporting**
```python
# Compliance reporting system
class ComplianceReporter:
    def __init__(self, db_session: Session):
        self.db = db_session
    
    def generate_gdpr_report(self, user_id: str) -> Dict:
        """Generate GDPR compliance report for user"""
        # Get all user data
        user_data = self.db.query(User).filter(User.id == user_id).first()
        user_files = self.db.query(UserFile).filter(UserFile.user_id == user_id).all()
        chat_sessions = self.db.query(ChatSession).filter(ChatSession.user_id == user_id).all()
        
        # Get data processing activities
        processing_activities = self.db.query(AuditEvent).filter(
            AuditEvent.user_id == user_id,
            AuditEvent.event_type == "data_processing"
        ).all()
        
        return {
            "user_id": user_id,
            "personal_data": {
                "email": user_data.email if user_data else None,
                "first_name": user_data.first_name if user_data else None,
                "last_name": user_data.last_name if user_data else None,
                "organization": user_data.organization.name if user_data and user_data.organization else None
            },
            "data_inventory": {
                "files_count": len(user_files),
                "files_total_size": sum(f.size for f in user_files),
                "chat_sessions_count": len(chat_sessions),
                "data_retention_period": "7 years"
            },
            "processing_activities": [
                {
                    "activity": event.action,
                    "timestamp": event.timestamp.isoformat(),
                    "details": event.details
                }
                for event in processing_activities
            ],
            "data_subject_rights": {
                "right_to_access": True,
                "right_to_rectification": True,
                "right_to_erasure": True,
                "right_to_portability": True,
                "right_to_object": True
            }
        }
    
    def generate_sox_report(self, organization_id: str, start_date: datetime, end_date: datetime) -> Dict:
        """Generate SOX compliance report"""
        # Get all financial data access
        financial_access = self.db.query(AuditEvent).filter(
            AuditEvent.organization_id == organization_id,
            AuditEvent.resource_type == "financial_document",
            AuditEvent.timestamp >= start_date,
            AuditEvent.timestamp <= end_date
        ).all()
        
        # Get user access patterns
        user_access = self.db.query(
            AuditEvent.user_id,
            func.count(AuditEvent.id).label('access_count')
        ).filter(
            AuditEvent.organization_id == organization_id,
            AuditEvent.timestamp >= start_date,
            AuditEvent.timestamp <= end_date
        ).group_by(AuditEvent.user_id).all()
        
        return {
            "organization_id": organization_id,
            "report_period": {
                "start_date": start_date.isoformat(),
                "end_date": end_date.isoformat()
            },
            "financial_data_access": {
                "total_access_events": len(financial_access),
                "unique_users": len(set(e.user_id for e in financial_access)),
                "access_by_user": [
                    {
                        "user_id": user_id,
                        "access_count": count
                    }
                    for user_id, count in user_access
                ]
            },
            "compliance_status": {
                "segregation_of_duties": self._check_segregation_of_duties(organization_id),
                "access_controls": self._check_access_controls(organization_id),
                "audit_trail_completeness": self._check_audit_trail_completeness(organization_id)
            }
        }
```

---

## 🚨 **Security Monitoring & Incident Response**

### **1. Real-Time Security Monitoring**
```python
# Security monitoring and alerting system
class SecurityMonitor:
    def __init__(self, redis_client: Redis, alert_service: AlertService):
        self.redis = redis_client
        self.alert_service = alert_service
        self.suspicious_activities = []
    
    def monitor_login_attempts(self, user_id: str, ip_address: str, success: bool):
        """Monitor login attempts for suspicious patterns"""
        key = f"login_attempts:{ip_address}"
        
        if success:
            # Reset counter on successful login
            self.redis.delete(key)
        else:
            # Increment failed attempts counter
            attempts = self.redis.incr(key)
            self.redis.expire(key, 3600)  # 1 hour window
            
            if attempts >= 5:
                self._trigger_brute_force_alert(user_id, ip_address, attempts)
    
    def monitor_data_access_patterns(self, user_id: str, resource_type: str, action: str):
        """Monitor data access for unusual patterns"""
        # Check for bulk data access
        recent_access = self.redis.lrange(f"recent_access:{user_id}", 0, 100)
        access_count = len([a for a in recent_access if json.loads(a)['resource_type'] == resource_type])
        
        if access_count > 50:  # Threshold for bulk access
            self._trigger_bulk_access_alert(user_id, resource_type, access_count)
        
        # Record access
        access_record = {
            "timestamp": datetime.utcnow().isoformat(),
            "resource_type": resource_type,
            "action": action
        }
        self.redis.lpush(f"recent_access:{user_id}", json.dumps(access_record))
        self.redis.ltrim(f"recent_access:{user_id}", 0, 99)  # Keep last 100 records
    
    def monitor_file_operations(self, user_id: str, operation: str, file_count: int):
        """Monitor file operations for suspicious activity"""
        if operation == "delete" and file_count > 10:
            self._trigger_bulk_delete_alert(user_id, file_count)
        
        if operation == "download" and file_count > 20:
            self._trigger_bulk_download_alert(user_id, file_count)
    
    def _trigger_brute_force_alert(self, user_id: str, ip_address: str, attempts: int):
        """Trigger brute force attack alert"""
        alert = {
            "type": "brute_force_attack",
            "severity": "high",
            "user_id": user_id,
            "ip_address": ip_address,
            "attempts": attempts,
            "timestamp": datetime.utcnow().isoformat()
        }
        
        self.alert_service.send_alert(alert)
        self._log_security_event("brute_force_detected", alert)
    
    def _trigger_bulk_access_alert(self, user_id: str, resource_type: str, count: int):
        """Trigger bulk data access alert"""
        alert = {
            "type": "bulk_data_access",
            "severity": "medium",
            "user_id": user_id,
            "resource_type": resource_type,
            "count": count,
            "timestamp": datetime.utcnow().isoformat()
        }
        
        self.alert_service.send_alert(alert)
        self._log_security_event("bulk_access_detected", alert)
```

### **2. Incident Response System**
```python
# Automated incident response system
class IncidentResponseSystem:
    def __init__(self, db_session: Session, security_monitor: SecurityMonitor):
        self.db = db_session
        self.security_monitor = security_monitor
    
    def handle_security_incident(self, incident_type: str, user_id: str, details: Dict):
        """Handle security incident with automated response"""
        incident = SecurityIncident(
            id=str(uuid.uuid4()),
            incident_type=incident_type,
            user_id=user_id,
            severity=self._determine_severity(incident_type),
            status="active",
            details=details,
            created_at=datetime.utcnow()
        )
        
        self.db.add(incident)
        self.db.commit()
        
        # Take automated response actions
        if incident_type == "brute_force_attack":
            self._block_suspicious_ip(details.get('ip_address'))
            self._notify_user_security_team(incident)
        
        elif incident_type == "bulk_data_access":
            self._temporarily_restrict_user_access(user_id)
            self._notify_data_protection_officer(incident)
        
        elif incident_type == "unauthorized_access":
            self._invalidate_all_user_sessions(user_id)
            self._force_password_reset(user_id)
            self._notify_user_and_admin(incident)
    
    def _block_suspicious_ip(self, ip_address: str):
        """Block suspicious IP address"""
        # Add to blocked IPs list
        self.redis.sadd("blocked_ips", ip_address)
        
        # Set expiration (24 hours)
        self.redis.expire("blocked_ips", 86400)
    
    def _temporarily_restrict_user_access(self, user_id: str):
        """Temporarily restrict user access"""
        # Add to restricted users list
        self.redis.setex(f"restricted_user:{user_id}", 3600, "true")  # 1 hour
    
    def _invalidate_all_user_sessions(self, user_id: str):
        """Invalidate all user sessions"""
        session_manager.invalidate_all_user_sessions(user_id)
    
    def _force_password_reset(self, user_id: str):
        """Force user to reset password"""
        # Generate password reset token
        reset_token = self._generate_password_reset_token(user_id)
        
        # Store token with expiration
        self.redis.setex(f"password_reset:{user_id}", 3600, reset_token)
        
        # Send password reset email
        self._send_password_reset_email(user_id, reset_token)
```

---

## 📋 **Regulatory Compliance**

### **1. GDPR Compliance**
```python
# GDPR compliance implementation
class GDPRCompliance:
    def __init__(self, db_session: Session, encryption_service: DataEncryption):
        self.db = db_session
        self.encryption = encryption_service
    
    def handle_data_subject_request(self, user_id: str, request_type: str) -> Dict:
        """Handle GDPR data subject requests"""
        if request_type == "access":
            return self._provide_data_access(user_id)
        elif request_type == "portability":
            return self._provide_data_portability(user_id)
        elif request_type == "erasure":
            return self._handle_data_erasure(user_id)
        elif request_type == "rectification":
            return self._handle_data_rectification(user_id)
        else:
            raise ValueError(f"Unknown request type: {request_type}")
    
    def _provide_data_access(self, user_id: str) -> Dict:
        """Provide complete data access to user"""
        # Get all user data
        user_data = self.db.query(User).filter(User.id == user_id).first()
        user_files = self.db.query(UserFile).filter(UserFile.user_id == user_id).all()
        chat_sessions = self.db.query(ChatSession).filter(ChatSession.user_id == user_id).all()
        
        return {
            "personal_data": {
                "id": user_data.id,
                "email": user_data.email,
                "first_name": user_data.first_name,
                "last_name": user_data.last_name,
                "organization": user_data.organization.name if user_data.organization else None,
                "created_at": user_data.created_at.isoformat(),
                "last_login": user_data.last_login.isoformat() if user_data.last_login else None
            },
            "files": [
                {
                    "id": f.id,
                    "filename": f.filename,
                    "size": f.size,
                    "uploaded_at": f.uploaded_at.isoformat(),
                    "content_type": f.content_type
                }
                for f in user_files
            ],
            "chat_sessions": [
                {
                    "id": s.id,
                    "title": s.title,
                    "created_at": s.created_at.isoformat(),
                    "message_count": len(s.messages)
                }
                for s in chat_sessions
            ],
            "data_processing_activities": self._get_processing_activities(user_id)
        }
    
    def _handle_data_erasure(self, user_id: str) -> Dict:
        """Handle right to be forgotten (data erasure)"""
        try:
            # Anonymize user data instead of complete deletion
            user = self.db.query(User).filter(User.id == user_id).first()
            if user:
                user.email = f"deleted_user_{user_id[:8]}@deleted.local"
                user.first_name = "Deleted"
                user.last_name = "User"
                user.is_deleted = True
                user.deleted_at = datetime.utcnow()
            
            # Delete user files from S3
            user_files = self.db.query(UserFile).filter(UserFile.user_id == user_id).all()
            for file_record in user_files:
                s3_manager.delete_file(file_record.s3_key)
                self.db.delete(file_record)
            
            # Delete chat sessions
            chat_sessions = self.db.query(ChatSession).filter(ChatSession.user_id == user_id).all()
            for session in chat_sessions:
                self.db.delete(session)
            
            # Invalidate all sessions
            session_manager.invalidate_all_user_sessions(user_id)
            
            self.db.commit()
            
            return {"status": "success", "message": "Data erasure completed"}
            
        except Exception as e:
            self.db.rollback()
            return {"status": "error", "message": f"Data erasure failed: {str(e)}"}
    
    def _provide_data_portability(self, user_id: str) -> str:
        """Provide data in portable format (JSON)"""
        data = self._provide_data_access(user_id)
        
        # Create portable JSON file
        portable_data = {
            "export_info": {
                "exported_at": datetime.utcnow().isoformat(),
                "user_id": user_id,
                "format_version": "1.0"
            },
            "user_data": data
        }
        
        # Save to temporary file
        temp_file = f"/tmp/onyx_export_{user_id}_{int(time.time())}.json"
        with open(temp_file, 'w') as f:
            json.dump(portable_data, f, indent=2, default=str)
        
        return temp_file
```

### **2. SOC 2 Compliance**
```python
# SOC 2 compliance framework
class SOC2Compliance:
    def __init__(self, db_session: Session):
        self.db = db_session
    
    def generate_control_evidence(self, control_id: str, period_start: datetime, period_end: datetime) -> Dict:
        """Generate evidence for SOC 2 controls"""
        if control_id == "CC6.1":
            return self._generate_access_control_evidence(period_start, period_end)
        elif control_id == "CC6.2":
            return self._generate_authentication_evidence(period_start, period_end)
        elif control_id == "CC6.3":
            return self._generate_authorization_evidence(period_start, period_end)
        elif control_id == "CC7.1":
            return self._generate_data_encryption_evidence(period_start, period_end)
        elif control_id == "CC8.1":
            return self._generate_audit_logging_evidence(period_start, period_end)
        else:
            raise ValueError(f"Unknown control ID: {control_id}")
    
    def _generate_access_control_evidence(self, start: datetime, end: datetime) -> Dict:
        """Generate evidence for access control (CC6.1)"""
        # Get access control events
        access_events = self.db.query(AuditEvent).filter(
            AuditEvent.event_type == "access_control",
            AuditEvent.timestamp >= start,
            AuditEvent.timestamp <= end
        ).all()
        
        # Get user access patterns
        user_access = self.db.query(
            AuditEvent.user_id,
            func.count(AuditEvent.id).label('access_count')
        ).filter(
            AuditEvent.event_type == "data_access",
            AuditEvent.timestamp >= start,
            AuditEvent.timestamp <= end
        ).group_by(AuditEvent.user_id).all()
        
        return {
            "control_id": "CC6.1",
            "control_name": "Logical Access Security",
            "evidence_type": "access_control_logs",
            "period": {
                "start": start.isoformat(),
                "end": end.isoformat()
            },
            "access_control_events": len(access_events),
            "unique_users_accessed": len(user_access),
            "access_patterns": [
                {
                    "user_id": user_id,
                    "access_count": count
                }
                for user_id, count in user_access
            ],
            "compliance_status": "compliant"
        }
    
    def _generate_data_encryption_evidence(self, start: datetime, end: datetime) -> Dict:
        """Generate evidence for data encryption (CC7.1)"""
        # Get encryption events
        encryption_events = self.db.query(AuditEvent).filter(
            AuditEvent.event_type == "encryption",
            AuditEvent.timestamp >= start,
            AuditEvent.timestamp <= end
        ).all()
        
        # Get file encryption status
        encrypted_files = self.db.query(UserFile).filter(
            UserFile.encrypted == True,
            UserFile.uploaded_at >= start,
            UserFile.uploaded_at <= end
        ).count()
        
        total_files = self.db.query(UserFile).filter(
            UserFile.uploaded_at >= start,
            UserFile.uploaded_at <= end
        ).count()
        
        encryption_percentage = (encrypted_files / total_files * 100) if total_files > 0 else 100
        
        return {
            "control_id": "CC7.1",
            "control_name": "System Operations",
            "evidence_type": "encryption_logs",
            "period": {
                "start": start.isoformat(),
                "end": end.isoformat()
            },
            "encryption_events": len(encryption_events),
            "files_encrypted": encrypted_files,
            "total_files": total_files,
            "encryption_percentage": round(encryption_percentage, 2),
            "compliance_status": "compliant" if encryption_percentage >= 95 else "non_compliant"
        }
```

---

## 🎯 **Security Best Practices Implementation**

### **1. Secure Development Lifecycle**
```python
# Security testing and validation
class SecurityValidator:
    def __init__(self):
        self.owasp_checks = OWASPChecker()
        self.dependency_scanner = DependencyScanner()
    
    def validate_input(self, input_data: str, input_type: str) -> bool:
        """Validate input against security threats"""
        # SQL injection check
        if self._contains_sql_injection(input_data):
            raise SecurityException("SQL injection attempt detected")
        
        # XSS check
        if self._contains_xss(input_data):
            raise SecurityException("XSS attempt detected")
        
        # Path traversal check
        if self._contains_path_traversal(input_data):
            raise SecurityException("Path traversal attempt detected")
        
        return True
    
    def scan_dependencies(self) -> Dict:
        """Scan dependencies for vulnerabilities"""
        return self.dependency_scanner.scan()
    
    def perform_security_tests(self) -> Dict:
        """Perform comprehensive security tests"""
        return {
            "owasp_top_10": self.owasp_checks.run_all_checks(),
            "dependency_vulnerabilities": self.scan_dependencies(),
            "configuration_security": self._check_configuration_security(),
            "encryption_validation": self._validate_encryption_implementation()
        }
```

### **2. Security Configuration Management**
```yaml
# Security configuration template
security:
  authentication:
    jwt:
      secret_key: "${JWT_SECRET_KEY}"
      algorithm: "HS256"
      expiration_hours: 24
    mfa:
      enabled: true
      totp_window: 1
      backup_codes_count: 10
  
  encryption:
    algorithm: "AES-256-GCM"
    key_rotation_days: 90
    encrypt_pii: true
  
  session_management:
    timeout_minutes: 1440  # 24 hours
    max_concurrent_sessions: 5
    secure_cookies: true
    http_only: true
    same_site: "strict"
  
  rate_limiting:
    requests_per_minute: 100
    burst_limit: 200
    window_size_minutes: 1
  
  audit_logging:
    enabled: true
    log_level: "INFO"
    retention_days: 2555  # 7 years
    sensitive_data_masking: true
  
  data_protection:
    anonymization_enabled: true
    data_retention_days: 2555  # 7 years
    gdpr_compliance: true
    right_to_erasure: true
```

---

## 🎉 **Conclusion**

Onyx's comprehensive security and compliance framework provides enterprise-grade protection that meets the most stringent security requirements. With multi-layer security architecture, comprehensive audit logging, regulatory compliance features, and automated incident response, Onyx ensures your data remains secure and compliant.

**Key Security Advantages:**
- **Defense in Depth**: Multiple security layers protecting your data
- **Regulatory Compliance**: Built-in GDPR, SOC 2, and other compliance features
- **Real-time Monitoring**: Proactive security monitoring and incident response
- **Data Protection**: End-to-end encryption and comprehensive data isolation
- **Audit Trail**: Complete audit logging for compliance and forensics

**Ready to secure your AI-powered document management?** Deploy Onyx with confidence, knowing your data is protected by enterprise-grade security controls.

---

*For security assessments, compliance audits, or custom security implementations, contact our security team or visit our security documentation portal.*
