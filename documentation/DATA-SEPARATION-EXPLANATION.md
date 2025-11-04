# Data Separation in Onyx - Visual Explanation

## 🎯 Data Separation Layer (Datentrennungsschicht)

This diagram illustrates how Onyx ensures complete data isolation between users, guaranteeing that each user's information remains private and inaccessible to others.

### **For Non-Technical Users:**

**Onyx uses a secure data separation architecture where each user gets their own private data vault, completely isolated from all other users.** When you use Onyx, your chat sessions, messages, and files are stored in a dedicated section that only you can access - think of it like having your own private room in a building where no one else has a key. The system automatically tags every piece of your data with your unique user ID, ensuring that even if multiple people use Onyx at the same time, their data is kept in separate, secure compartments that never overlap or become visible to each other. This means your private conversations, uploaded documents, and all associated information are completely siloed, so you can be confident that other users cannot see, access, or interact with your data under any circumstances.

### **For IT Professionals:**

**Onyx implements a multi-layered data separation architecture using database-level isolation mechanisms, including foreign key constraints linking all data records to user_id, Row-Level Security (RLS) policies that enforce user-level access control at the database engine level, and tenant-aware Redis caching with namespaced keys to prevent cross-user cache access.** Each user's data - including chat sessions stored in the `chat_session` table with `user_id` foreign keys, messages in the `chat_message` table linked via `chat_session_id` → `user_id` relationships, and files in the `user_file` table with direct `user_id` references - is physically and logically separated through database schema design, query filtering, and application-level authorization checks. The system enforces complete data isolation through three mechanisms: (1) **Database Constraints**: Every table has `user_id` foreign keys that create a hard dependency on user ownership, (2) **RLS Policies**: PostgreSQL Row-Level Security policies automatically filter queries to only return rows where `user_id` matches the authenticated user, preventing SQL injection or direct database access from bypassing application security, and (3) **Application-Level Filtering**: All API endpoints validate user ownership before returning data, and SQLAlchemy session scoping automatically adds `WHERE user_id = current_user.id` to every query. This multi-layered approach ensures that even if an application bug occurs, the database-level RLS policies act as a fail-safe, making it technically impossible for one user to access another user's data without explicit system-level permissions.

---

## 📊 Visual Diagram Explanation

The diagram shows:

```
┌─────────────────────────────────────────────────────────┐
│              DATENTRENNUNGSSCHICHT                      │
│           (Data Separation Layer)                       │
└─────────────────────────────────────────────────────────┘

┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│   USER 1         │  │   USER 2         │  │   USER 3         │
│                  │  │                  │  │                  │
│  Chat Sessions   │  │  Chat Sessions   │  │  Chat Sessions   │
│  Messages        │  │  Messages        │  │  Messages        │
│  Files           │  │  Files           │  │  Files           │
│                  │  │                  │  │                  │
│  [Isolated]      │  │  [Isolated]      │  │  [Isolated]      │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

**Key Points:**
- Each user has completely separate data compartments
- No cross-user data visibility or access
- Logical and physical separation at database level
- Guaranteed privacy and security standards

---

## 🔐 Technical Implementation

### **Database-Level Isolation:**
- **Foreign Key Constraints**: `user_id` in all tables
- **Row-Level Security (RLS)**: Automatic query filtering
- **Schema Isolation**: Multi-tenant schema separation

### **Application-Level Isolation:**
- **User Context**: Every request filters by `user_id`
- **Ownership Verification**: API endpoints validate user ownership
- **Tenant-Aware Caching**: Redis keys namespaced by tenant_id

### **Security Guarantees:**
- ✅ Users can only see their own data
- ✅ Database policies prevent SQL bypasses
- ✅ Application logic enforces isolation
- ✅ Cache isolation prevents cross-user access

---

**Document Version:** 1.0  
**Last Updated:** [Current Date]

