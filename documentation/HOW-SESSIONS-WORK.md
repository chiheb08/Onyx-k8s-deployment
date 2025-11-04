# How Sessions Work in Onyx - User Guide

## 🎯 **Quick Answer**

**Sessions in Onyx are completely separate for each user.** Your data is isolated and secure, with multiple layers of protection ensuring that users can only access their own information.

---

## 📚 **What Are Sessions in Onyx?**

### **Think of Sessions Like This:**

#### **1. Chat Sessions = Individual Conversations**
- **Like**: Having separate notebooks for different topics
- **Each user has their own notebooks** - you can't see other people's notebooks
- **Each conversation is private** - only you can see your chat history
- **Persistent storage** - your conversations are saved permanently

#### **2. User Sessions = Your Login State**
- **Like**: Having a key to your own house
- **Each user has their own key** - you can't use someone else's key
- **Temporary storage** - your login expires after a while for security
- **Automatic renewal** - your key gets refreshed as you use the system

#### **3. Project Sessions = Grouped Conversations**
- **Like**: Having folders for related conversations
- **Can be shared with team members** - with proper permissions
- **Organized by topic** - all related chats in one place
- **Persistent storage** - saved permanently

---

## 🔐 **How Is Data Separated Between Users?**

### **Multi-Layer Data Isolation:**

#### **1. Database Level (PostgreSQL)**
```
Every piece of data is linked to a user ID:
- Chat sessions: user_id field
- Messages: linked to chat_session → user_id
- Files: user_id field
- Projects: user_id field
- Settings: user_id field

Result: Users can only see their own data
```

#### **2. Application Level (API)**
```
Every API request checks:
- Is the user authenticated?
- Does this data belong to the user?
- Does the user have permission?

Result: No cross-user data access possible
```

#### **3. Tenant Level (Organization)**
```
Each organization has:
- Separate database schema
- Isolated user management
- Complete data separation

Result: Organizations can't see each other's data
```

### **Real-World Example:**

#### **User A (Alice) and User B (Bob):**
```
Alice's Data:
- Chat Session 1: "Project Planning"
- Chat Session 2: "Budget Discussion"
- Files: project_doc.pdf, budget.xlsx
- Projects: "Q1 Planning", "Marketing"

Bob's Data:
- Chat Session 1: "Sales Strategy"
- Chat Session 2: "Client Meeting"
- Files: sales_pitch.pptx, client_list.csv
- Projects: "Sales Q1", "Client Relations"

Result: Alice can't see Bob's data, and vice versa
```

---

## 💾 **How Is Data Stored?**

### **Database Storage (PostgreSQL):**

#### **1. Chat Sessions Table:**
```sql
chat_session:
- id: unique session identifier
- user_id: links to user (Alice or Bob)
- description: "Project Planning"
- time_created: when session was created
- time_updated: last activity
```

#### **2. Messages Table:**
```sql
chat_message:
- id: unique message identifier
- chat_session_id: links to chat session
- message: "What's our budget for Q1?"
- message_type: "user" or "assistant"
- time_created: when message was sent
```

#### **3. Users Table:**
```sql
user:
- id: unique user identifier
- email: alice@company.com
- role: "admin" or "user"
- preferences: user settings
```

### **Cache Storage (Redis):**

#### **1. Authentication Sessions:**
```
Key: "auth:session:abc123"
Value: {
    "user_id": "alice-uuid",
    "tenant_id": "company-tenant",
    "expires_at": "2024-01-02T10:00:00Z"
}
TTL: 24 hours
```

#### **2. Active Sessions:**
```
Key: "session:chat-123"
Value: {
    "user_id": "alice-uuid",
    "last_accessed": "2024-01-01T15:30:00Z",
    "data": "session_state"
}
TTL: 1 hour
```

---

## 🔄 **How Do Sessions Work in Practice?**

### **User Login Process:**

#### **Step 1: User Enters Credentials**
```
User: Enters email and password
System: Validates credentials against database
Result: Credentials are correct
```

#### **Step 2: System Creates Session**
```
System: Creates JWT token with user ID
System: Stores session in Redis cache
System: Returns token to user's browser
Result: User is now logged in
```

#### **Step 3: User Makes Requests**
```
User: Sends request with token
System: Validates token and extracts user ID
System: Filters all data by user ID
Result: User only sees their own data
```

### **Chat Session Creation:**

#### **Step 1: User Creates New Chat**
```
User: Clicks "New Chat"
System: Creates chat_session record with user_id
System: Returns session ID to user
Result: New chat session is created
```

#### **Step 2: User Sends Message**
```
User: Types message and hits send
System: Validates user owns the session
System: Creates message record linked to session
System: Processes message with AI
Result: Message is stored and response generated
```

#### **Step 3: User Views Chat History**
```
User: Opens chat session
System: Validates user owns the session
System: Retrieves all messages for that session
System: Returns messages to user
Result: User sees their chat history
```

---

## 🛡️ **Security and Privacy**

### **Data Protection Mechanisms:**

#### **1. Authentication Security:**
```
- JWT tokens with expiration
- Secure token generation
- Automatic token refresh
- Session timeout for inactivity
```

#### **2. Authorization Security:**
```
- Every request validates user identity
- Database queries filter by user_id
- API endpoints check permissions
- No cross-user data access possible
```

#### **3. Data Encryption:**
```
- Passwords are hashed (never stored in plain text)
- Sensitive data is encrypted at rest
- All communication uses HTTPS/TLS
- Database connections are encrypted
```

### **Privacy Guarantees:**

#### **1. Complete Data Isolation:**
```
- Users can only see their own data
- No access to other users' conversations
- No access to other users' files
- No access to other users' projects
```

#### **2. Secure Data Storage:**
```
- Data is stored in encrypted databases
- Regular security backups
- Access logs for audit trails
- Compliance with data protection regulations
```

---

## 📊 **Session Management Features**

### **For Regular Users:**

#### **1. Chat Session Management:**
```
- Create new chat sessions
- Rename existing sessions
- Delete old sessions
- Search through chat history
- Export chat conversations
```

#### **2. User Session Management:**
```
- Login/logout functionality
- Password management
- Profile settings
- Preference configuration
- Session timeout handling
```

#### **3. Project Session Management:**
```
- Create project folders
- Add files to projects
- Share projects with team members
- Organize conversations by topic
- Manage project permissions
```

### **For Administrators:**

#### **1. User Management:**
```
- Create user accounts
- Manage user permissions
- Monitor user activity
- Handle user sessions
- Manage user data
```

#### **2. System Management:**
```
- Monitor system performance
- Manage database storage
- Handle session cleanup
- Monitor security events
- Manage system backups
```

#### **3. Security Management:**
```
- Monitor authentication events
- Track data access patterns
- Handle security incidents
- Manage access controls
- Audit user activities
```

---

## 🔍 **Troubleshooting Common Issues**

### **"I Can't See My Chat Sessions"**

#### **Possible Causes:**
```
1. Not logged in properly
2. Session expired
3. Browser cache issues
4. Network connectivity problems
```

#### **Solutions:**
```
1. Log out and log back in
2. Clear browser cache
3. Check internet connection
4. Contact administrator if issue persists
```

### **"I Can See Someone Else's Data"**

#### **This Should Never Happen:**
```
If you can see someone else's data, this is a serious security issue:
1. Immediately log out
2. Contact your administrator
3. Report the security incident
4. Do not access any data until resolved
```

### **"My Sessions Keep Expiring"**

#### **Possible Causes:**
```
1. Session timeout settings
2. Browser not storing tokens
3. System maintenance
4. Security policies
```

#### **Solutions:**
```
1. Check if you're inactive for too long
2. Enable "Remember Me" if available
3. Contact administrator about timeout settings
4. Check system status
```

---

## 📈 **Performance and Scalability**

### **How Onyx Handles Many Users:**

#### **1. Database Optimization:**
```
- Indexed queries for fast data retrieval
- Partitioned tables for large datasets
- Connection pooling for efficiency
- Query optimization for performance
```

#### **2. Caching Strategy:**
```
- Redis cache for session data
- Database query caching
- CDN for static content
- Memory optimization
```

#### **3. Load Balancing:**
```
- Multiple application servers
- Load balancer distribution
- Database read replicas
- Redis clustering
```

### **Scalability Features:**

#### **1. Horizontal Scaling:**
```
- Add more servers as needed
- Distribute load across servers
- Scale database and cache
- Handle more concurrent users
```

#### **2. Vertical Scaling:**
```
- Increase server resources
- Optimize database performance
- Improve memory allocation
- Enhance CPU utilization
```

---

## 🎯 **Best Practices for Users**

### **Session Management:**

#### **1. Regular Maintenance:**
```
- Delete old chat sessions you don't need
- Organize conversations into projects
- Clean up uploaded files
- Update your profile regularly
```

#### **2. Security Practices:**
```
- Use strong passwords
- Log out when done
- Don't share your login credentials
- Report suspicious activity
```

#### **3. Performance Tips:**
```
- Close unused chat sessions
- Limit file uploads to reasonable sizes
- Use projects to organize conversations
- Clear browser cache periodically
```

---

## 📞 **Getting Help**

### **If You Have Issues:**

#### **1. Check Common Solutions:**
```
- Review this guide
- Check system status
- Try logging out and back in
- Clear browser cache
```

#### **2. Contact Support:**
```
- Contact your administrator
- Provide specific error messages
- Describe what you were trying to do
- Include screenshots if helpful
```

#### **3. Report Security Issues:**
```
- Immediately report any security concerns
- Don't access suspicious data
- Contact administrator right away
- Follow security incident procedures
```

---

## 🎉 **Summary**

### **Key Points About Onyx Sessions:**

1. **Complete Data Isolation** - Each user's data is completely separate
2. **Multi-Layer Security** - Authentication, authorization, and data protection
3. **Persistent Storage** - Your conversations are saved permanently
4. **Real-Time Updates** - Live chat and instant synchronization
5. **Scalable Architecture** - Handles many users efficiently
6. **Privacy Protection** - Your data is secure and private

### **What This Means for You:**

- **Your conversations are private** - only you can see them
- **Your data is secure** - multiple layers of protection
- **Your sessions are persistent** - they're saved permanently
- **Your access is controlled** - proper permissions and authentication
- **Your privacy is protected** - complete data isolation

### **Remember:**

- **Always log out when done** - for security
- **Use strong passwords** - to protect your account
- **Report any issues** - to your administrator
- **Keep your data organized** - using projects and folders

This architecture ensures that your data is completely isolated, secure, and accessible only to you, while providing a seamless user experience across all your devices and sessions.

---

## 📋 **Technical Summary & Step-by-Step Explanation**

### **For Non-Technical Users:**

**Sessions in Onyx work like a secure personal vault system:** When you log in, the system creates a unique digital key (JWT token) that identifies you, stores it temporarily in fast memory (Redis cache) for quick access, and uses it to ensure every piece of data you create or view is automatically tagged with your user ID and stored in the database (PostgreSQL) with permanent isolation. Each time you send a message, upload a file, or create a chat, the system follows a strict security process: it validates your identity token, checks that you own the data you're accessing, creates database records linked to your user ID, and stores temporary session information in cache for fast retrieval, ensuring complete data separation between users at multiple layers (database queries filter by user_id, API endpoints validate ownership, and Redis cache stores sessions with tenant isolation).

### **For Technical Users:**

**Sessions in Onyx implement a multi-layered authentication and authorization architecture:** The system uses JWT tokens (stored in Redis with TTL expiration) for authentication, PostgreSQL with Row-Level Security (RLS) and user_id foreign keys for data persistence and isolation, and Redis cache for session state management with tenant-based key namespacing. The technical flow follows this sequence: (1) User authenticates → FastAPI validates credentials against PostgreSQL user table → JWT token generated with user_id and tenant_id claims → Token stored in Redis with key pattern `auth:session:{token_hash}` and TTL of 24 hours → Token returned to client as HTTP-only cookie or Authorization header; (2) User makes API request → NGINX extracts token → FastAPI middleware validates token signature and expiration → Extracts user_id from token claims → Sets current_user context; (3) Data operations → All database queries automatically filter by user_id (via SQLAlchemy session scoping) → PostgreSQL RLS policies enforce additional isolation → API endpoints verify ownership before returning data → Results cached in Redis with tenant-scoped keys; (4) Session management → Chat sessions stored in `chat_session` table with `user_id` foreign key → Messages linked via `chat_session_id` → Active sessions cached in Redis with pattern `session:{session_id}` for sub-second retrieval → Session expiration handled by Redis TTL and background cleanup jobs → All operations are transactional and ACID-compliant for data integrity.
