# Onyx Sessions Architecture - Complete Guide

## 🎯 **Overview**

This guide explains how sessions work in Onyx, including how data is stored separately, how data is separated from one user to another, and the complete session management architecture.

---

## 📚 **What Are Sessions in Onyx?**

### **Types of Sessions:**

#### **1. Chat Sessions**
- **What they are**: Individual conversation threads between users and AI
- **Purpose**: Store chat history, messages, and conversation context
- **Scope**: Each session belongs to a specific user
- **Persistence**: Stored permanently in the database

#### **2. User Sessions (Authentication)**
- **What they are**: Authentication sessions for logged-in users
- **Purpose**: Manage user login state and permissions
- **Scope**: One per logged-in user
- **Persistence**: Stored in Redis with expiration

#### **3. Project Sessions**
- **What they are**: Sessions associated with specific projects
- **Purpose**: Group related conversations and files
- **Scope**: Can be shared among team members
- **Persistence**: Stored in the database

---

## 🏗️ **Session Architecture**

### **Database Layer (PostgreSQL):**

#### **Chat Session Table:**
```sql
CREATE TABLE chat_session (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES user(id) ON DELETE CASCADE,
    persona_id INTEGER REFERENCES persona(id),
    description TEXT,
    onyxbot_flow BOOLEAN DEFAULT FALSE,
    deleted BOOLEAN DEFAULT FALSE,
    shared_status VARCHAR(20) DEFAULT 'PRIVATE',
    current_alternate_model VARCHAR(255),
    slack_thread_id VARCHAR(255),
    project_id INTEGER REFERENCES user_project(id),
    llm_override JSONB,
    temperature_override FLOAT,
    prompt_override JSONB,
    time_created TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    time_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

#### **Chat Message Table:**
```sql
CREATE TABLE chat_message (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_session_id UUID REFERENCES chat_session(id) ON DELETE CASCADE,
    parent_message_id UUID REFERENCES chat_message(id),
    message TEXT,
    message_type VARCHAR(20),
    token_count INTEGER,
    time_created TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    -- Additional fields for tool calls, streaming, etc.
);
```

#### **User Table:**
```sql
CREATE TABLE user (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    hashed_password VARCHAR(255),
    role VARCHAR(20) DEFAULT 'BASIC',
    is_verified BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    -- Additional user preferences and settings
);
```

### **Cache Layer (Redis):**

#### **Authentication Sessions:**
```
Key: "auth:session:{token}"
Value: {
    "sub": "user_id",
    "tenant_id": "tenant_id",
    "expires_at": "timestamp"
}
TTL: 24 hours (configurable)
```

#### **Session Data:**
```
Key: "session:{session_id}"
Value: {
    "user_id": "user_id",
    "last_accessed": "timestamp",
    "data": "session_data"
}
TTL: 1 hour (configurable)
```

---

## 🔐 **User Data Separation**

### **Database-Level Separation:**

#### **1. User ID Foreign Keys:**
```sql
-- Every table that stores user data has a user_id foreign key
chat_session.user_id -> user.id
chat_message.chat_session_id -> chat_session.id -> user.id
user_file.user_id -> user.id
user_project.user_id -> user.id
persona.user_id -> user.id
```

#### **2. Row-Level Security (RLS):**
```sql
-- Users can only access their own data
CREATE POLICY user_data_policy ON chat_session
    FOR ALL TO authenticated_user
    USING (user_id = current_user_id());

CREATE POLICY user_data_policy ON chat_message
    FOR ALL TO authenticated_user
    USING (chat_session_id IN (
        SELECT id FROM chat_session WHERE user_id = current_user_id()
    ));
```

#### **3. Tenant Isolation:**
```sql
-- Each tenant has its own schema/database
-- Users are isolated by tenant_id
-- Data is completely separated between tenants
```

### **Application-Level Separation:**

#### **1. Authentication Middleware:**
```python
async def current_user(
    user: User | None = Depends(optional_fastapi_current_user)
) -> User | None:
    # Validates user authentication
    # Returns user object with permissions
    # Handles token validation and refresh
```

#### **2. Permission Checks:**
```python
def get_chat_sessions_by_user(
    user_id: UUID | None,
    deleted: bool | None,
    db_session: Session
) -> list[ChatSession]:
    # Only returns sessions belonging to the user
    # Filters by user_id in database query
    # Enforces data isolation
```

#### **3. API Endpoint Protection:**
```python
@router.get("/get-user-chat-sessions")
def get_user_chat_sessions(
    user: User | None = Depends(current_user),
    db_session: Session = Depends(get_session)
) -> ChatSessionsResponse:
    # Automatically filters by authenticated user
    # No access to other users' data
    # Secure by default
```

---

## 💾 **Data Storage Architecture**

### **Session Data Storage:**

#### **1. Chat Sessions:**
```
Storage: PostgreSQL (persistent)
Structure: Relational database with foreign keys
Isolation: user_id foreign key + RLS policies
Backup: Regular database backups
Retention: Permanent (until deleted by user)
```

#### **2. Chat Messages:**
```
Storage: PostgreSQL (persistent)
Structure: Hierarchical (parent-child relationships)
Isolation: Linked to chat_session via foreign key
Backup: Regular database backups
Retention: Permanent (until session deleted)
```

#### **3. User Files:**
```
Storage: PostgreSQL + File System
Structure: Metadata in DB, files on disk
Isolation: user_id foreign key
Backup: Database + file system backups
Retention: Until deleted by user
```

#### **4. Authentication Sessions:**
```
Storage: Redis (temporary)
Structure: Key-value with TTL
Isolation: Token-based authentication
Backup: Not backed up (temporary data)
Retention: 24 hours (configurable)
```

### **Data Flow:**

#### **1. User Login:**
```
1. User provides credentials
2. System validates credentials
3. Creates authentication session in Redis
4. Returns session token to client
5. Client stores token for future requests
```

#### **2. Chat Session Creation:**
```
1. User creates new chat session
2. System creates record in chat_session table
3. Links session to user via user_id
4. Returns session ID to client
5. Client can now send messages to session
```

#### **3. Message Storage:**
```
1. User sends message
2. System validates user permissions
3. Creates message record in chat_message table
4. Links message to chat_session via chat_session_id
5. Message is now part of conversation history
```

---

## 🔒 **Security and Isolation**

### **Multi-Layer Security:**

#### **1. Authentication Layer:**
```
- JWT tokens with expiration
- Redis-based session storage
- Automatic token refresh
- Secure token generation
```

#### **2. Authorization Layer:**
```
- Role-based access control (RBAC)
- User-specific data filtering
- API endpoint protection
- Permission validation
```

#### **3. Data Layer:**
```
- Foreign key constraints
- Row-level security policies
- Tenant isolation
- Database-level permissions
```

#### **4. Application Layer:**
```
- Input validation
- SQL injection prevention
- XSS protection
- CSRF protection
```

### **Data Isolation Mechanisms:**

#### **1. User Isolation:**
```
- Every user's data is linked to their user_id
- Database queries always filter by user_id
- No cross-user data access possible
- Automatic data separation
```

#### **2. Tenant Isolation:**
```
- Each tenant has separate database schema
- Complete data separation between tenants
- No cross-tenant data access
- Isolated user management
```

#### **3. Session Isolation:**
```
- Each chat session belongs to one user
- Sessions cannot be accessed by other users
- Message history is private to session owner
- Project sessions can be shared (with permissions)
```

---

## 📊 **Session Management**

### **Chat Session Lifecycle:**

#### **1. Creation:**
```
User Action: Click "New Chat"
System Action: 
  - Create chat_session record
  - Link to user via user_id
  - Set initial persona
  - Return session ID
Client Action: Store session ID, navigate to chat
```

#### **2. Usage:**
```
User Action: Send message
System Action:
  - Validate user permissions
  - Create chat_message record
  - Link to chat_session
  - Process message with AI
  - Return response
Client Action: Display message in chat
```

#### **3. Deletion:**
```
User Action: Delete chat session
System Action:
  - Mark session as deleted
  - Cascade delete messages
  - Clean up associated data
  - Update user interface
Client Action: Remove from chat list
```

### **User Session Lifecycle:**

#### **1. Login:**
```
User Action: Enter credentials
System Action:
  - Validate credentials
  - Create Redis session
  - Generate JWT token
  - Set expiration
Client Action: Store token, redirect to dashboard
```

#### **2. Active Session:**
```
User Action: Use application
System Action:
  - Validate token on each request
  - Refresh token if needed
  - Load user data
  - Process requests
Client Action: Send token with requests
```

#### **3. Logout:**
```
User Action: Click logout
System Action:
  - Invalidate Redis session
  - Clear token
  - Clean up temporary data
Client Action: Clear stored token, redirect to login
```

---

## 🔄 **Session Synchronization**

### **Real-time Updates:**

#### **1. WebSocket Connections:**
```
- Each user has WebSocket connection
- Real-time message updates
- Live typing indicators
- Instant notifications
```

#### **2. Database Triggers:**
```
- Automatic data consistency
- Real-time updates
- Event-driven architecture
- Scalable design
```

#### **3. Cache Invalidation:**
```
- Redis cache updates
- Real-time data refresh
- Performance optimization
- Consistency maintenance
```

### **Cross-Device Synchronization:**

#### **1. Session Sharing:**
```
- Sessions stored in database
- Accessible from any device
- Real-time synchronization
- Consistent experience
```

#### **2. State Management:**
```
- Client-side state store
- Server-side validation
- Conflict resolution
- Data consistency
```

---

## 📈 **Performance and Scalability**

### **Database Optimization:**

#### **1. Indexing:**
```sql
-- Optimized indexes for session queries
CREATE INDEX idx_chat_session_user_id ON chat_session(user_id);
CREATE INDEX idx_chat_session_created ON chat_session(time_created);
CREATE INDEX idx_chat_message_session ON chat_message(chat_session_id);
CREATE INDEX idx_chat_message_created ON chat_message(time_created);
```

#### **2. Partitioning:**
```sql
-- Partition chat_message table by date
CREATE TABLE chat_message_2024_01 PARTITION OF chat_message
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

#### **3. Caching:**
```
- Redis for session data
- Database query caching
- CDN for static content
- Memory optimization
```

### **Scalability Patterns:**

#### **1. Horizontal Scaling:**
```
- Multiple application servers
- Load balancer distribution
- Database read replicas
- Redis clustering
```

#### **2. Vertical Scaling:**
```
- Increased server resources
- Database optimization
- Memory allocation
- CPU utilization
```

---

## 🛠️ **Configuration and Management**

### **Session Configuration:**

#### **1. Timeout Settings:**
```python
# Authentication session timeout
SESSION_EXPIRE_TIME_SECONDS = 86400  # 24 hours

# Chat session retention
CHAT_SESSION_RETENTION_DAYS = 365

# Message retention
MESSAGE_RETENTION_DAYS = 365
```

#### **2. Storage Settings:**
```python
# Database connection
DATABASE_URL = "postgresql://user:pass@host:port/db"

# Redis connection
REDIS_URL = "redis://host:port/db"

# File storage
FILE_STORAGE_PATH = "/app/storage"
```

### **Monitoring and Logging:**

#### **1. Session Metrics:**
```
- Active sessions count
- Session creation rate
- Session duration
- Error rates
```

#### **2. Performance Metrics:**
```
- Database query times
- Redis response times
- API response times
- Memory usage
```

#### **3. Security Logs:**
```
- Authentication attempts
- Permission violations
- Data access patterns
- Security events
```

---

## 🎯 **Summary**

### **Key Points:**

1. **Sessions are completely isolated by user** - Each user can only access their own data
2. **Data is stored in PostgreSQL** - Persistent, relational storage with foreign key relationships
3. **Authentication uses Redis** - Fast, temporary session storage with automatic expiration
4. **Multi-layer security** - Authentication, authorization, database, and application layers
5. **Real-time synchronization** - WebSocket connections for live updates
6. **Scalable architecture** - Designed for horizontal and vertical scaling

### **Data Separation Mechanisms:**

1. **User ID Foreign Keys** - Every table links to user.id
2. **Row-Level Security** - Database policies prevent cross-user access
3. **Tenant Isolation** - Complete separation between different organizations
4. **API Protection** - All endpoints validate user permissions
5. **Application Logic** - Business logic enforces data isolation

### **Session Types:**

1. **Chat Sessions** - Individual conversations (persistent)
2. **User Sessions** - Authentication state (temporary)
3. **Project Sessions** - Grouped conversations (persistent, shareable)

This architecture ensures that user data is completely isolated, secure, and scalable while providing a seamless user experience across devices and sessions.
