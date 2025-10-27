# Simple Onyx Sessions Architecture

## 🎯 **Easy-to-Understand Session Flow**

This diagram shows how sessions work in Onyx in simple, step-by-step terms.

---

## 📱 **Step 1: User Login**

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    USER LOGIN FLOW                                      │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  User                    │  Onyx System              │  Database                      │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  1. Enter Email     │  │  │  2. Check Password  │  │  │  3. Find User Record    │  │
│  │     & Password      │  │  │  4. Create Session  │  │  │     - user_id: 123      │  │
│  │                     │  │  │  5. Generate Token  │  │  │     - email: alice@...  │  │
│  │                     │  │  │  6. Store in Redis  │  │  │     - role: admin       │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
│                           │                           │                               │
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  7. Get Token       │  │  │  8. Send Token      │  │  │  9. User Data Ready     │  │
│  │  8. Store in Browser│  │  │     to User         │  │  │     for Session         │  │
│  │                     │  │  │                     │  │  │                         │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

What Happens:
1. User enters email and password
2. System checks if password is correct
3. System finds user in database (user_id: 123)
4. System creates a session for this user
5. System generates a secure token
6. System stores session in Redis cache
7. System sends token to user's browser
8. User's browser stores the token
9. User is now logged in and ready to use Onyx
```

---

## 💬 **Step 2: Create Chat Session**

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                CREATE CHAT SESSION FLOW                                 │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  User                    │  Onyx System              │  Database                      │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  1. Click "New Chat"│  │  │  2. Check Token     │  │  │  3. Create Chat Record  │  │
│  │                     │  │  │  3. Get User ID     │  │  │     - session_id: abc   │  │
│  │                     │  │  │  4. Create Session  │  │  │     - user_id: 123      │  │
│  │                     │  │  │  5. Link to User    │  │  │     - description: ""   │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
│                           │                           │                               │
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  6. Get Session ID  │  │  │  7. Send Session ID │  │  │  8. Chat Ready for      │  │
│  │  7. Start Chatting  │  │  │     to User         │  │  │     Messages            │  │
│  │                     │  │  │                     │  │  │                         │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

What Happens:
1. User clicks "New Chat" button
2. System checks if user is logged in (using token)
3. System gets user ID from token (user_id: 123)
4. System creates new chat session
5. System links chat session to user
6. System sends session ID to user
7. User can now start chatting
8. Chat session is ready for messages
```

---

## 📝 **Step 3: Send Message**

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                   SEND MESSAGE FLOW                                     │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  User                    │  Onyx System              │  Database                      │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  1. Type Message    │  │  │  2. Check Token     │  │  │  3. Save Message        │  │
│  │     "Hello AI"      │  │  │  3. Check Session   │  │  │     - message_id: xyz   │  │
│  │  2. Click Send      │  │  │  4. Process with AI │  │  │     - session_id: abc   │  │
│  │                     │  │  │  5. Generate Reply  │  │  │     - content: "Hello"  │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
│                           │                           │                               │
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  6. See AI Reply    │  │  │  7. Send Reply      │  │  │  8. Save AI Reply      │  │
│  │     "Hi! How can I  │  │  │     to User         │  │  │     - message_id: def   │  │
│  │     help you?"      │  │  │                     │  │  │     - session_id: abc   │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  │     - content: "Hi!..." │  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

What Happens:
1. User types message and clicks send
2. System checks if user is logged in
3. System checks if user owns this chat session
4. System processes message with AI
5. System generates AI reply
6. System sends reply to user
7. User sees AI reply in chat
8. Both messages are saved in database
```

---

## 🔐 **Step 4: Data Separation (How Users Stay Separate)**

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                DATA SEPARATION LAYER                                    │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Alice's Data (User ID: 123)    │  Bob's Data (User ID: 456)    │  Database Structure    │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────┐  │  ┌─────────────────────────┐  │  ┌─────────────────┐  │
│  │  Chat Sessions:             │  │  │  Chat Sessions:         │  │  │  chat_session   │  │
│  │  - Session 1: "Work Chat"   │  │  │  - Session 1: "Sales"  │  │  │  ┌─────────────┐ │  │
│  │  - Session 2: "Personal"    │  │  │  - Session 2: "Client" │  │  │  │ id          │ │  │
│  │  - Session 3: "Project A"   │  │  │  - Session 3: "Team"   │  │  │  │ user_id     │ │  │
│  │                             │  │  │                         │  │  │  │ description │ │  │
│  │  Messages:                   │  │  │  Messages:              │  │  │  └─────────────┘ │  │
│  │  - "How's the project?"     │  │  │  - "Sales are up 20%"   │  │  │                 │  │
│  │  - "Let's meet tomorrow"    │  │  │  - "Client called"      │  │  │  chat_message  │  │
│  │  - "Great work!"            │  │  │  - "Team meeting at 3"  │  │  │  ┌─────────────┐ │  │
│  └─────────────────────────────┘  │  └─────────────────────────┘  │  │  │ id          │ │  │
│                                   │                               │  │  │ session_id  │ │  │
│  ┌─────────────────────────────┐  │  ┌─────────────────────────┐  │  │  │ content     │ │  │
│  │  Files:                     │  │  │  Files:                 │  │  │  │ user_id     │ │  │
│  │  - project_doc.pdf          │  │  │  - sales_report.xlsx    │  │  │  └─────────────┘ │  │
│  │  - budget_2024.xlsx         │  │  │  - client_list.csv      │  │  │                 │  │
│  │  - meeting_notes.txt        │  │  │  - team_roster.pdf      │  │  │  user           │  │
│  └─────────────────────────────┘  │  └─────────────────────────┘  │  │  ┌─────────────┐ │  │
│                                   │                               │  │  │ id          │ │  │
│  Alice CANNOT see:                │  Bob CANNOT see:              │  │  │ email       │ │  │
│  - Bob's chat sessions            │  - Alice's chat sessions      │  │  │ password    │ │  │
│  - Bob's messages                 │  - Alice's messages           │  │  │ role        │ │  │
│  - Bob's files                    │  - Alice's files              │  │  └─────────────┘ │  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

How Data Separation Works:
1. Every chat session has a user_id field
2. Every message is linked to a chat session
3. Every file belongs to a specific user
4. Database queries always filter by user_id
5. Alice can only see data where user_id = 123
6. Bob can only see data where user_id = 456
7. No cross-user data access is possible
```

---

## 🏗️ **Step 5: Complete Architecture Overview**

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              COMPLETE ONYX SESSIONS ARCHITECTURE                       │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  User Browser            │  Onyx Server            │  Redis Cache          │  Database │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────┐  │  ┌─────┐ │
│  │  Stored Token       │  │  │  Authentication     │  │  │  Session Data   │  │  │User │ │
│  │  - JWT Token        │  │  │  - Check Token      │  │  │  - user_id: 123 │  │  │Data │ │
│  │  - Session ID       │  │  │  - Get User ID      │  │  │  - expires: 24h │  │  │     │ │
│  │  - User Preferences │  │  │  - Validate Access  │  │  │  - permissions  │  │  │     │ │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────┘  │  └─────┘ │
│                           │                           │                       │         │
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────┐  │  ┌─────┐ │
│  │  Chat Interface     │  │  │  Chat Management    │  │  │  Active Sessions│  │  │Chat │ │
│  │  - Send Messages    │  │  │  - Create Sessions │  │  │  - session_id   │  │  │Data │ │
│  │  - View History     │  │  │  - Store Messages  │  │  │  - last_access  │  │  │     │ │
│  │  - Real-time Updates│  │  │  - Process AI      │  │  │  - user_data    │  │  │     │ │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────┘  │  └─────┘ │
│                           │                           │                       │         │
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────┐  │  ┌─────┐ │
│  │  File Management    │  │  │  File Processing    │  │  │  WebSocket      │  │  │File │ │
│  │  - Upload Files     │  │  │  - Store Files      │  │  │  - Live Updates │  │  │Data │ │
│  │  - View Files       │  │  │  - Process Files    │  │  │  - Real-time    │  │  │     │ │
│  │  - Delete Files     │  │  │  - Link to User     │  │  │  - Notifications│  │  │     │ │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────┘  │  └─────┘ │
└─────────────────────────────────────────────────────────────────────────────────────────┘

Data Flow:
1. User logs in → Token stored in browser
2. User creates chat → Session stored in database with user_id
3. User sends message → Message stored with session_id and user_id
4. AI processes message → Response generated and stored
5. User sees response → Real-time update via WebSocket
6. All data is filtered by user_id → Complete separation
```

---

## 🔄 **Step 6: Session Lifecycle**

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                  SESSION LIFECYCLE                                     │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Login Phase              │  Active Phase              │  Logout Phase                 │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  1. Enter Credentials│  │  │  1. Use Application │  │  │  1. Click Logout        │  │
│  │  2. Validate Login  │  │  │  2. Send Messages   │  │  │  2. Clear Token         │  │
│  │  3. Create Token    │  │  │  3. Upload Files    │  │  │  3. Clear Session       │  │
│  │  4. Store in Redis  │  │  │  4. Create Chats    │  │  │  4. Redirect to Login   │  │
│  │  5. Return Token    │  │  │  5. Real-time Updates│  │  │  5. Session Expired     │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
│                           │                           │                               │
│  Duration: ~2 seconds     │  Duration: Hours/Days     │  Duration: ~1 second        │
│  Data: Token created      │  Data: All user data      │  Data: Token destroyed       │
│  Storage: Redis + DB      │  Storage: DB + Redis      │  Storage: Cleared            │
└─────────────────────────────────────────────────────────────────────────────────────────┘

Session States:
- LOGIN: User authenticates and gets token
- ACTIVE: User uses application normally
- EXPIRED: Token expires after 24 hours
- LOGOUT: User logs out or session expires
```

---

## 🎯 **Key Points Summary**

### **How Sessions Work:**
1. **User logs in** → Gets a secure token
2. **User creates chat** → Session linked to user ID
3. **User sends message** → Message stored with user ID
4. **AI responds** → Response linked to same session
5. **Data stays separate** → Each user only sees their own data

### **Data Separation:**
- **Every piece of data has a user_id**
- **Database queries filter by user_id**
- **Users can only see their own data**
- **No cross-user access possible**

### **Security:**
- **JWT tokens for authentication**
- **Redis for session storage**
- **Database for persistent data**
- **Multiple layers of protection**

### **Real-time Features:**
- **WebSocket connections for live updates**
- **Instant message delivery**
- **Live typing indicators**
- **Real-time notifications**

This simple architecture ensures that each user's data is completely separate and secure while providing a smooth, real-time experience! 🎉
