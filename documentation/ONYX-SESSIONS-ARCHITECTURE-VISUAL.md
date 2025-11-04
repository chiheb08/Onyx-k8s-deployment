# Onyx Sessions Architecture - Complete Visual Diagram

## 🎯 Complete Session Flow Diagram

This diagram shows the complete end-to-end flow of how sessions work in Onyx, including all components and security layers.

```mermaid
graph TB
    %% User Layer
    subgraph User["👤 USER BROWSER"]
        U1["User Login - Email + Password"]
        U2["Store JWT Token - HTTP-only Cookie"]
        U3["Send API Request - With JWT Token"]
        U4["Create Chat Session - POST /api/chat/session"]
        U5["Send Message - POST /api/chat/message"]
    end

    %% Gateway Layer
    subgraph Gateway["🔐 NGINX GATEWAY"]
        N1[Receive Request]
        N2["Extract JWT Token - From Cookie/Header"]
        N3[Route to API Server]
    end

    %% API Server Layer
    subgraph API["⚙️ API SERVER (FastAPI)"]
        A1["Validate JWT Token - Signature + Expiration"]
        A2["Extract user_id - from Token Claims"]
        A3["Set current_user Context - Tenant-aware"]
        A4["Check Ownership - Verify user_id"]
        A5[Process Request]
        A6[Return Response]
    end

    %% Cache Layer
    subgraph Redis["💾 REDIS CACHE"]
        R1["auth:session:token - TTL: 24h - user_id, tenant_id"]
        R2["session:session_id - TTL: 1h - user_id, last_accessed"]
        R3["Tenant-aware Keys - Namespace Isolation"]
    end

    %% Database Layer
    subgraph PostgreSQL["🗄️ POSTGRESQL DATABASE"]
        P1["user Table - id, email, password_hash, role, preferences"]
        P2["chat_session Table - id, user_id FK, description, time_created"]
        P3["chat_message Table - id, chat_session_id FK, message, message_type"]
        P4["Row-Level Security - RLS Policies"]
    end

    %% Authentication Flow
    U1 -->|1. POST /api/auth/login| N1
    N1 -->|2. Extract credentials| N2
    N2 -->|3. Forward to API| A1
    A1 -->|4. Validate credentials| P1
    P1 -->|5. Check password hash| A2
    A2 -->|6. Generate JWT Token| R1
    R1 -->|7. Store in Redis - auth:session:token| A3
    A3 -->|8. Return token to client| N3
    N3 -->|9. Set HTTP-only cookie| U2

    %% Session Creation Flow
    U4 -->|10. POST /api/chat/session - JWT in header| N1
    N1 -->|11. Extract token| N2
    N2 -->|12. Validate token| A1
    A1 -->|13. Check Redis cache| R1
    R1 -->|14. Token valid| A2
    A2 -->|15. Extract user_id| A3
    A3 -->|16. Create session record| P2
    P2 -->|17. user_id FK constraint| A4
    A4 -->|18. RLS policy check| P4
    P4 -->|19. Access granted| A5
    A5 -->|20. Return session_id| A6
    A6 -->|21. Cache session| R2
    R2 -->|22. Return to client| U2

    %% Message Flow
    U5 -->|23. POST /api/chat/message - JWT + session_id| N1
    N1 -->|24. Extract token| N2
    N2 -->|25. Validate token| A1
    A1 -->|26. Check Redis| R1
    R1 -->|27. Token valid| A2
    A2 -->|28. Extract user_id| A3
    A3 -->|29. Verify session ownership| P2
    P2 -->|30. Check user_id matches| A4
    A4 -->|31. RLS policy enforcement| P4
    P4 -->|32. Access granted| A5
    A5 -->|33. Create message record| P3
    P3 -->|34. chat_session_id FK| A6
    A6 -->|35. Return message| U2

    %% Data Isolation Mechanisms
    P4 -.->|RLS Policy: user_id = current_user_id| P2
    P4 -.->|RLS Policy: session belongs to user| P3
    R3 -.->|Tenant Isolation: tenant_id in key| R1
    A3 -.->|Tenant Context: Set from token| P1

    %% Styling
    classDef userClass fill:#e1f5ff,stroke:#01579b,stroke-width:2px
    classDef gatewayClass fill:#fff3e0,stroke:#e65100,stroke-width:2px
    classDef apiClass fill:#f3e5f5,stroke:#4a148c,stroke-width:2px
    classDef cacheClass fill:#ffebee,stroke:#b71c1c,stroke-width:2px
    classDef dbClass fill:#e8f5e9,stroke:#1b5e20,stroke-width:2px

    class U1,U2,U3,U4,U5 userClass
    class N1,N2,N3 gatewayClass
    class A1,A2,A3,A4,A5,A6 apiClass
    class R1,R2,R3 cacheClass
    class P1,P2,P3,P4 dbClass
```

---

## 📋 Component Breakdown

### **1. User Browser Layer**
- **Login**: User enters credentials (email + password)
- **Token Storage**: JWT token stored in HTTP-only cookie
- **Requests**: All API requests include JWT token
- **Session Management**: Creates and manages chat sessions
- **Message Sending**: Sends messages to chat sessions

### **2. NGINX Gateway Layer**
- **Request Routing**: Receives all incoming requests
- **Token Extraction**: Extracts JWT from cookie/header
- **Load Balancing**: Routes to appropriate API server
- **SSL Termination**: Handles HTTPS/TLS encryption

### **3. API Server Layer (FastAPI)**
- **Token Validation**: Validates JWT signature and expiration
- **User Extraction**: Extracts `user_id` and `tenant_id` from token
- **Context Setting**: Sets `current_user` context for request
- **Ownership Verification**: Checks user owns the data being accessed
- **Request Processing**: Processes business logic
- **Response Return**: Returns data filtered by user_id

### **4. Redis Cache Layer**
- **Authentication Cache**: Stores JWT tokens with TTL (24h)
  - Key: `auth:session:{token}`
  - Value: `{user_id, tenant_id, expires_at}`
- **Session Cache**: Stores active session data (TTL: 1h)
  - Key: `session:{session_id}`
  - Value: `{user_id, last_accessed, data}`
- **Tenant Isolation**: Uses tenant-aware key namespacing

### **5. PostgreSQL Database Layer**
- **User Table**: Stores user accounts and credentials
  - Primary Key: `id` (UUID)
  - Fields: `email`, `password_hash`, `role`, `preferences`
- **Chat Session Table**: Stores chat conversations
  - Primary Key: `id` (UUID)
  - Foreign Key: `user_id` → `user.id`
  - Fields: `description`, `time_created`, `time_updated`
- **Chat Message Table**: Stores individual messages
  - Primary Key: `id` (UUID)
  - Foreign Key: `chat_session_id` → `chat_session.id`
  - Fields: `message`, `message_type`, `token_count`
- **Row-Level Security (RLS)**: Database-level policies enforcing user isolation

---

## 🔄 Complete Flow Explanation

### **Step 1-9: Authentication Flow**
1. User submits login credentials
2. NGINX extracts credentials and routes to API Server
3. API Server validates credentials against PostgreSQL `user` table
4. If valid, generates JWT token with `user_id` and `tenant_id` claims
5. Stores token in Redis with key `auth:session:{token}` (TTL: 24h)
6. Returns token to client as HTTP-only cookie
7. Client stores token for future requests

### **Step 10-22: Session Creation Flow**
8. User creates new chat session (POST with JWT token)
9. NGINX extracts JWT token from request
10. API Server validates token signature and expiration
11. Checks Redis cache for token validity
12. Extracts `user_id` from token claims
13. Creates new record in `chat_session` table with `user_id` FK
14. PostgreSQL RLS policy verifies user owns the session
15. Caches session data in Redis for fast access
16. Returns `session_id` to client

### **Step 23-35: Message Flow**
17. User sends message (POST with JWT + session_id)
18. NGINX extracts JWT token
19. API Server validates token and extracts `user_id`
20. Verifies user owns the chat session (ownership check)
21. PostgreSQL RLS policy enforces user isolation
22. Creates message record in `chat_message` table with `chat_session_id` FK
23. Returns message confirmation to client

---

## 🔐 Security Layers

### **Layer 1: Authentication (JWT Tokens)**
- Secure token generation using secrets
- Token signature validation
- Expiration handling (24h TTL)
- Token refresh mechanism

### **Layer 2: Authorization (Ownership Verification)**
- User ID extraction from token
- Ownership checks before data access
- API endpoint permission validation
- Role-based access control (RBAC)

### **Layer 3: Database Isolation (RLS Policies)**
- Row-Level Security policies
- Foreign key constraints
- User ID filtering in all queries
- Tenant schema isolation

### **Layer 4: Cache Isolation (Tenant-Aware Keys)**
- Tenant ID in Redis keys
- Namespace isolation
- TTL-based expiration
- Cache invalidation on logout

---

## 📊 Data Isolation Guarantees

### **User Isolation:**
- ✅ Every table has `user_id` foreign key
- ✅ All queries filter by `user_id`
- ✅ RLS policies enforce user-level access
- ✅ No cross-user data access possible

### **Tenant Isolation:**
- ✅ `tenant_id` in JWT token claims
- ✅ Tenant-aware Redis key namespacing
- ✅ Schema-level separation (multi-tenant)
- ✅ Complete data isolation between organizations

### **Session Isolation:**
- ✅ Each chat session belongs to one user
- ✅ Messages linked via `chat_session_id` → `user_id`
- ✅ Ownership verification on every request
- ✅ Session cache scoped by user

---

## 🎯 Key Takeaways

1. **Multi-Layer Security**: Authentication (JWT) → Authorization (Ownership) → Database (RLS) → Cache (Tenant Isolation)

2. **Complete Data Isolation**: Every data record is linked to `user_id` via foreign keys, enforced by RLS policies

3. **Fast Access**: Redis cache stores sessions and tokens for sub-second retrieval

4. **Persistent Storage**: PostgreSQL stores all data permanently with ACID guarantees

5. **Scalable Architecture**: Stateless API servers with Redis caching enable horizontal scaling

---

**Document Version:** 1.0  
**Last Updated:** [Current Date]  
**Visualization:** Mermaid Diagram

