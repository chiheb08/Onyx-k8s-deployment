# Onyx Architecture Diagrams
## Visual Explanations of How Onyx Works

---

## 🏗️ **High-Level System Architecture**

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              ONYX PLATFORM                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐            │
│  │   Web Browser   │    │   Mobile App    │    │   API Clients   │            │
│  │   (Users)       │    │   (Users)       │    │   (Integrations)│            │
│  └─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘            │
│            │                      │                      │                    │
│            └──────────────────────┼──────────────────────┘                    │
│                                   │                                           │
│  ┌─────────────────────────────────┴─────────────────────────────────────────┐ │
│  │                        NGINX (Load Balancer)                            │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │ │
│  │  │   Web Server    │  │   API Server    │  │   Admin Panel   │          │ │
│  │  │   (Frontend)    │  │   (Backend)     │  │   (Management)  │          │ │
│  │  └─────────┬───────┘  └─────────┬───────┘  └─────────┬───────┘          │ │
│  └────────────┼────────────────────┼─────────────────────┼─────────────────┘ │
│               │                    │                     │                   │
│  ┌────────────┴────────────────────┼─────────────────────┴─────────────────┐ │
│  │                    Security & Authentication Layer                     │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │ │
│  │  │   JWT Tokens    │  │   MFA System    │  │   RBAC Engine   │          │ │
│  │  │   (Sessions)    │  │   (2FA)         │  │   (Permissions) │          │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘          │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                        Data Processing Layer                          │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │ │
│  │  │   AI Engine     │  │   File Processor│  │   Search Engine │          │ │
│  │  │   (Understanding)│  │   (Documents)   │  │   (Vespa)       │          │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘          │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                          Storage Layer                                │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐          │ │
│  │  │   PostgreSQL    │  │   Redis Cache   │  │   Private S3    │          │ │
│  │  │   (Metadata)    │  │   (Sessions)    │  │   (Files)       │          │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘          │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔐 **Security Architecture Flow**

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            USER LOGIN PROCESS                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  User enters credentials                                                        │
│           │                                                                    │
│           ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Email/Password │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Credential     │                                                           │
│  │  Verification   │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  MFA Check      │                                                           │
│  │  (2FA Code)     │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  JWT Token      │                                                           │
│  │  Generation     │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Session        │                                                           │
│  │  Creation       │                                                           │
│  └─────────────────┘                                                           │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 💾 **Data Flow Architecture**

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            DOCUMENT UPLOAD FLOW                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  User uploads file                                                              │
│           │                                                                    │
│           ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  File Validation│                                                           │
│  │  (Size, Type)   │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Encryption     │                                                           │
│  │  (AES-256)      │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Private S3     │                                                           │
│  │  Storage        │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  AI Processing  │                                                           │
│  │  (Text Extract) │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Search Index   │                                                           │
│  │  (Vespa)        │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Metadata       │                                                           │
│  │  (PostgreSQL)   │                                                           │
│  └─────────────────┘                                                           │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔍 **Search Architecture**

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            AI SEARCH PROCESS                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  User asks question                                                             │
│           │                                                                    │
│           ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Query          │                                                           │
│  │  Processing     │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  AI Embedding   │                                                           │
│  │  Generation     │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Vector Search  │                                                           │
│  │  (Vespa)        │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Relevance      │                                                           │
│  │  Scoring        │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Results        │                                                           │
│  │  Ranking        │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Answer         │                                                           │
│  │  Generation     │                                                           │
│  └─────────────────┘                                                           │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 👥 **User Data Isolation**

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            DATA ISOLATION MODEL                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    Organization A                                      │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐        │   │
│  │  │   User A1       │  │   User A2       │  │   User A3       │        │   │
│  │  │   Documents     │  │   Documents     │  │   Documents     │        │   │
│  │  │   ┌─────────┐   │  │   ┌─────────┐   │  │   ┌─────────┐   │        │   │
│  │  │   │ File 1  │   │  │   │ File 1  │   │  │   │ File 1  │   │        │   │
│  │  │   │ File 2  │   │  │   │ File 2  │   │  │   │ File 2  │   │        │   │
│  │  │   │ File 3  │   │  │   │ File 3  │   │  │   │ File 3  │   │        │   │
│  │  │   └─────────┘   │  │   └─────────┘   │  │   └─────────┘   │        │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘        │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    Organization B                                      │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐        │   │
│  │  │   User B1       │  │   User B2       │  │   User B3       │        │   │
│  │  │   Documents     │  │   Documents     │  │   Documents     │        │   │
│  │  │   ┌─────────┐   │  │   ┌─────────┐   │  │   ┌─────────┐   │        │   │
│  │  │   │ File 1  │   │  │   │ File 1  │   │  │   │ File 1  │   │        │   │
│  │  │   │ File 2  │   │  │   │ File 2  │   │  │   │ File 2  │   │        │   │
│  │  │   │ File 3  │   │  │   │ File 3  │   │  │   │ File 3  │   │        │   │
│  │  │   └─────────┘   │  │   └─────────┘   │  │   └─────────┘   │        │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘        │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    Organization C                                      │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐        │   │
│  │  │   User C1       │  │   User C2       │  │   User C3       │        │   │
│  │  │   Documents     │  │   Documents     │  │   Documents     │        │   │
│  │  │   ┌─────────┐   │  │   ┌─────────┐   │  │   ┌─────────┐   │        │   │
│  │  │   │ File 1  │   │  │   │ File 1  │   │  │   │ File 1  │   │        │   │
│  │  │   │ File 2  │   │  │   │ File 2  │   │  │   │ File 2  │   │        │   │
│  │  │   │ File 3  │   │  │   │ File 3  │   │  │   │ File 3  │   │        │   │
│  │  │   └─────────┘   │  │   └─────────┘   │  │   └─────────┘   │        │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘        │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  🔒 Complete Physical and Logical Separation                                    │
│  📊 Each organization's data is completely isolated                            │
│  🚫 No cross-organization data access possible                                 │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔒 **Encryption Architecture**

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            ENCRYPTION LAYERS                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    Data in Transit (HTTPS/TLS)                        │   │
│  │  User Device ←→ Encrypted Connection ←→ Onyx Servers                   │   │
│  │  🔐 TLS 1.3 Encryption                                                │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    Data at Rest (AES-256)                             │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                    │   │
│  │  │   Files     │  │  Database   │  │   Cache     │                    │   │
│  │  │   🔐        │  │   🔐        │  │   🔐        │                    │   │
│  │  │ Encrypted   │  │ Encrypted   │  │ Encrypted   │                    │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    Application Level Encryption                       │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                    │   │
│  │  │   PII Data  │  │   Sessions  │  │   Metadata  │                    │   │
│  │  │   🔐        │  │   🔐        │  │   🔐        │                    │   │
│  │  │ Encrypted   │  │ Encrypted   │  │ Encrypted   │                    │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  🔑 Key Management:                                                             │
│  • Encryption keys are managed securely                                       │
│  • Keys are rotated regularly (90 days)                                       │
│  • Different keys for different data types                                     │
│  • Keys are never stored with encrypted data                                   │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 📊 **Session Management Flow**

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            SESSION LIFECYCLE                                  │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────┐                                                           │
│  │  User Login     │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Credential     │                                                           │
│  │  Verification   │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  JWT Token      │                                                           │
│  │  Generation     │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Session        │                                                           │
│  │  Storage        │                                                           │
│  │  (Redis)        │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Activity       │                                                           │
│  │  Monitoring     │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Session        │                                                           │
│  │  Expiration     │                                                           │
│  │  (24 hours)     │                                                           │
│  └─────────┬───────┘                                                           │
│            │                                                                    │
│            ▼                                                                    │
│  ┌─────────────────┐                                                           │
│  │  Auto Logout    │                                                           │
│  │  or Renewal     │                                                           │
│  └─────────────────┘                                                           │
│                                                                                 │
│  Security Features:                                                             │
│  • Maximum 5 concurrent sessions per user                                      │
│  • IP address tracking                                                         │
│  • Suspicious activity detection                                               │
│  • Automatic session invalidation on security events                           │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🚀 **Scalability Architecture**

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            SCALING STRATEGY                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    Load Balancer (NGINX)                              │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                    │   │
│  │  │   Server 1  │  │   Server 2  │  │   Server 3  │                    │   │
│  │  │   (Web)     │  │   (API)     │  │   (Admin)   │                    │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    Background Workers (Celery)                        │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                    │   │
│  │  │   Worker 1  │  │   Worker 2  │  │   Worker 3  │                    │   │
│  │  │ (Processing)│  │ (Indexing)  │  │  (Search)   │                    │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    Database Cluster                                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                    │   │
│  │  │ PostgreSQL  │  │ PostgreSQL  │  │ PostgreSQL  │                    │   │
│  │  │ (Primary)   │  │ (Replica)   │  │ (Replica)   │                    │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    Cache Cluster (Redis)                              │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                    │   │
│  │  │   Redis 1   │  │   Redis 2   │  │   Redis 3   │                    │   │
│  │  │ (Sessions)  │  │  (Cache)    │  │  (Queue)    │                    │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                 │
│  Scaling Benefits:                                                              │
│  • Horizontal scaling: Add more servers as needed                              │
│  • Load balancing: Distribute traffic evenly                                   │
│  • High availability: Multiple servers prevent downtime                        │
│  • Performance: Caching and background processing                              │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 🎯 **Key Security Principles**

### **1. Defense in Depth**
```
Layer 1: Physical Security (Private S3, Secure Data Centers)
Layer 2: Network Security (Firewalls, VPNs, Network Policies)
Layer 3: Application Security (Authentication, Authorization)
Layer 4: Data Security (Encryption, Access Controls)
Layer 5: Monitoring Security (Audit Logs, Incident Response)
```

### **2. Zero Trust Architecture**
```
Every Request → Verify Identity → Check Permissions → Log Activity → Allow/Deny
```

### **3. Principle of Least Privilege**
```
Users only get access to what they need for their job
Admins only get access to what they need to manage
Systems only get access to what they need to function
```

---

## 📋 **Compliance Features**

### **GDPR Compliance**
```
Right to Access → Export all user data
Right to Rectification → Edit personal information
Right to Erasure → Delete user data completely
Right to Portability → Download data in standard format
Right to Object → Opt out of data processing
```

### **SOC 2 Compliance**
```
Security → Access controls and encryption
Availability → System uptime and reliability
Processing Integrity → Data accuracy and completeness
Confidentiality → Data protection and privacy
Privacy → Personal information handling
```

---

## 🎉 **Summary**

These diagrams show how Onyx provides:
- **Complete Security**: Multiple layers of protection
- **Data Isolation**: Your data stays separate from others
- **Scalability**: Grows with your organization
- **Compliance**: Meets regulatory requirements
- **Performance**: Fast and responsive
- **Reliability**: High availability and backup

Onyx is designed to be both powerful and secure, giving you the tools you need to manage documents while keeping your data safe.

---

## 🧭 Simplified Interface Diagram (High-Level Services)

```
Users (Browser/Mobile/Integrations)
        |
        v
+------------------+
|   NGINX Gateway  |
|  (TLS, Routing)  |
+--------+---------+
         |
  +------+---------------------------+
  |                                  |
  v                                  v
+-------------------+        +--------------------+
|  Web App (UI)     |        |  API (Core Logic)  |
|  Next.js Frontend |        |  FastAPI Backend   |
+---------+---------+        +---------+----------+
          |                             |
          | UI calls                    | Business APIs
          |                             |
          v                             v
      [Session/Auth]                [Background Tasks]
          |                             |
          v                             v
+-------------------+        +--------------------+
|  Redis (Sessions) |        |  Celery Workers    |
+-------------------+        +---------+----------+
                                      |
                                      v
                          +------------------------+
                          |   Model Services (AI)  |
                          |  Embeddings/Inference  |
                          +-----------+------------+
                                      |
                                      v
+------------------+   +------------------+   +------------------+
|  PostgreSQL      |   |  Vespa/pgvector  |   |  Private S3      |
|  (Metadata)      |   |  (Search Index)  |   |  (Files)         |
+------------------+   +------------------+   +------------------+
```

---

## 🔄 End-to-End Request Workflows (Simplified)

### 1) Login
```
User → NGINX → Web App → API: POST /auth/login
API → Redis: create session (JWT/session token)
API → Web App: 200 + session token
Web App → Next requests include session → NGINX → API: authorized
```

### 2) Upload File
```
User → Web App → API: POST /files/upload (multipart)
API → Private S3: store encrypted file
API → PostgreSQL: create file metadata row
API → Celery: enqueue "process_document" task
Workers → S3: read file → Model Services: generate embeddings → Vespa/pgvector: index
API → Web App: 202 Accepted (processing) → UI shows status updates
```

### 3) Ask a Question (Search + Answer)
```
User → Web App → API: POST /search/query { question }
API → Model Services: get query embedding
API → Vespa/pgvector: semantic vector search
API → PostgreSQL: fetch metadata, permissions check
API → Web App: top results + snippets + sources
(Optional) API → Model Services: answer synthesis from retrieved docs
```

### 4) View My Files
```
User → Web App → API: GET /user/files
API → PostgreSQL: filter by user_id (isolation)
API → Web App: list of files with statuses
```

### 5) Delete a File
```
User → Web App → API: DELETE /user/files/{id}
API → PostgreSQL: ownership check → delete metadata
API → S3: delete object
API → Vespa/pgvector: remove from index
API → Web App: 200 OK
```

### 6) Logout
```
User → Web App → API: POST /auth/logout
API → Redis: invalidate session
API → Web App: 204 No Content
```

---

## 🧩 What Each Block Does (At a Glance)

- Web App: UI, session handling, calls API securely
- API: Authentication, authorization, business logic, auditing
- Redis: Sessions and short-lived caches
- Celery Workers: Background jobs (ingest, indexing, maintenance)
- Model Services: Embeddings and LLM-powered tasks
- PostgreSQL: Users, sessions, metadata, permissions
- Vespa/pgvector: Vector search for semantic retrieval
- Private S3: Encrypted document storage under your control

---
