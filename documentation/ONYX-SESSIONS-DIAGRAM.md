# Onyx Sessions Architecture Diagram

## 🎯 **Complete Session Architecture Overview**

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    ONYX SESSIONS ARCHITECTURE                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    CLIENT LAYER                                        │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Web Browser              │  Mobile App              │  API Client                    │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  Session Store      │  │  │  Session Store      │  │  │  Session Store          │  │
│  │  - JWT Token        │  │  │  - JWT Token        │  │  │  - API Key              │  │
│  │  - Session ID       │  │  │  - Session ID       │  │  │  - Session ID           │  │
│  │  - User Preferences │  │  │  - User Preferences │  │  │  - User Preferences     │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
│                           │                           │                               │
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  WebSocket          │  │  │  WebSocket          │  │  │  HTTP/HTTPS             │  │
│  │  - Real-time updates│  │  │  - Real-time updates│  │  │  - REST API calls       │  │
│  │  - Live chat        │  │  │  - Live chat        │  │  │  - Batch operations     │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    API GATEWAY LAYER                                   │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  NGINX Load Balancer     │  Authentication Middleware  │  Rate Limiting               │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  Request Routing    │  │  │  JWT Validation     │  │  │  Request Throttling     │  │
│  │  - Load balancing   │  │  │  - Token verification│  │  │  - Rate limiting        │  │
│  │  - SSL termination  │  │  │  - User extraction  │  │  │  - DDoS protection      │  │
│  │  - Health checks    │  │  │  - Permission check │  │  │  - Abuse prevention     │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    APPLICATION LAYER                                   │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  API Server              │  Web Server              │  Background Workers             │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  Session Management │  │  │  Session Management │  │  │  Session Cleanup        │  │
│  │  - Create sessions  │  │  │  - UI state         │  │  │  - Expired sessions     │  │
│  │  - Update sessions  │  │  │  - Real-time sync   │  │  │  - Data archiving       │  │
│  │  - Delete sessions  │  │  │  - WebSocket handling│  │  │  - Background tasks     │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
│                           │                           │                               │
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  Message Processing │  │  │  Message Processing │  │  │  Message Processing     │  │
│  │  - Send messages    │  │  │  - Display messages │  │  │  - AI processing        │  │
│  │  - Store messages   │  │  │  - Real-time updates│  │  │  - Response generation  │  │
│  │  - Process AI       │  │  │  - User interaction │  │  │  - Background tasks     │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    CACHE LAYER (REDIS)                                 │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Authentication Cache    │  Session Cache            │  Message Cache                  │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  JWT Tokens         │  │  │  Active Sessions    │  │  │  Recent Messages        │  │
│  │  - User ID          │  │  │  - Session data     │  │  │  - Message content      │  │
│  │  - Tenant ID        │  │  │  - User preferences │  │  │  - Message metadata     │  │
│  │  - Expiration       │  │  │  - Last accessed    │  │  │  - Message status       │  │
│  │  - Permissions      │  │  │  - Session state    │  │  │  - Message order        │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
│                           │                           │                               │
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  Session Tokens     │  │  │  User Data          │  │  │  WebSocket Connections  │  │
│  │  - Session ID       │  │  │  - User profile     │  │  │  - Connection mapping   │  │
│  │  - User ID          │  │  │  - User settings    │  │  │  - Message routing      │  │
│  │  - Session data     │  │  │  - User preferences │  │  │  - Real-time updates    │  │
│  │  - TTL              │  │  │  - User permissions │  │  │  - Connection state     │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    DATABASE LAYER (POSTGRESQL)                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  User Data               │  Session Data            │  Message Data                    │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  Users Table        │  │  │  Chat Sessions      │  │  │  Chat Messages          │  │
│  │  - User ID (PK)     │  │  │  - Session ID (PK)  │  │  │  - Message ID (PK)      │  │
│  │  - Email            │  │  │  - User ID (FK)     │  │  │  - Session ID (FK)      │  │
│  │  - Password Hash    │  │  │  - Persona ID (FK)  │  │  │  - Parent Message (FK)  │  │
│  │  - Role             │  │  │  - Description      │  │  │  - Message Content      │  │
│  │  - Permissions      │  │  │  - Shared Status    │  │  │  - Message Type         │  │
│  │  - Preferences      │  │  │  - Project ID (FK)  │  │  │  - Token Count          │  │
│  │  - Settings         │  │  │  - Time Created     │  │  │  - Time Created         │  │
│  │  - Last Login       │  │  │  - Time Updated     │  │  │  - Time Updated         │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
│                           │                           │                               │
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  User Projects      │  │  │  User Files         │  │  │  Tool Calls             │  │
│  │  - Project ID (PK)  │  │  │  - File ID (PK)     │  │  │  - Call ID (PK)         │  │
│  │  - User ID (FK)     │  │  │  - User ID (FK)     │  │  │  - Message ID (FK)      │  │
│  │  - Project Name     │  │  │  - File Name        │  │  │  - Tool Name            │  │
│  │  - Project Data     │  │  │  - File Path        │  │  │  - Tool Parameters      │  │
│  │  - Created Date     │  │  │  - File Size        │  │  │  - Tool Result          │  │
│  │  - Updated Date     │  │  │  - File Type        │  │  │  - Call Status          │  │
│  │  - Shared Status    │  │  │  - Upload Date      │  │  │  - Call Duration        │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    DATA ISOLATION LAYER                                │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  User Isolation          │  Tenant Isolation        │  Session Isolation              │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  Foreign Key Links  │  │  │  Schema Separation  │  │  │  Session Ownership      │  │
│  │  - user_id in all   │  │  │  - tenant_1 schema  │  │  │  - One user per session │  │
│  │    user tables      │  │  │  - tenant_2 schema  │  │  │  - Session permissions  │  │
│  │  - CASCADE deletes  │  │  │  - tenant_3 schema  │  │  │  - Access control       │  │
│  │  - Data integrity   │  │  │  - Complete isolation│  │  │  - Privacy protection   │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
│                           │                           │                               │
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  Row-Level Security │  │  │  Database Users     │  │  │  API Endpoint Security  │  │
│  │  - RLS policies     │  │  │  - tenant_1_user    │  │  │  - User validation      │  │
│  │  - Access control   │  │  │  - tenant_2_user    │  │  │  - Permission checks    │  │
│  │  - Data filtering   │  │  │  - tenant_3_user    │  │  │  - Session validation   │  │
│  │  - Security rules   │  │  │  - Isolated access  │  │  │  - Data protection      │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    SECURITY LAYER                                      │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Authentication          │  Authorization           │  Data Protection                │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  JWT Tokens         │  │  │  Role-Based Access  │  │  │  Encryption at Rest     │  │
│  │  - Secure generation│  │  │  - Admin role       │  │  │  - Database encryption  │  │
│  │  - Token validation │  │  │  - User role        │  │  │  - File encryption     │  │
│  │  - Token refresh    │  │  │  - Curator role     │  │  │  - Backup encryption   │  │
│  │  - Token expiration │  │  │  - Limited role     │  │  │  - Key management      │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
│                           │                           │                               │
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  Session Management │  │  │  Permission Checks  │  │  │  Encryption in Transit  │  │
│  │  - Session creation │  │  │  - API permissions  │  │  │  - HTTPS/TLS            │  │
│  │  - Session validation│  │  │  - Data permissions │  │  │  - WebSocket security   │  │
│  │  - Session cleanup  │  │  │  - Resource access  │  │  │  - API security         │  │
│  │  - Session security │  │  │  - Action permissions│  │  │  - Network security     │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    DATA FLOW DIAGRAM                                   │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  User Login Flow         │  Session Creation Flow    │  Message Flow                   │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  1. User enters     │  │  │  1. User clicks     │  │  │  1. User types message  │  │
│  │     credentials     │  │  │     "New Chat"      │  │  │  2. Client sends to API │  │
│  │  2. System validates│  │  │  2. System creates  │  │  │  3. API validates user  │  │
│  │     credentials     │  │  │     session record  │  │  │  4. API stores message  │  │
│  │  3. System creates  │  │  │  3. System links    │  │  │  5. API processes with  │  │
│  │     JWT token       │  │  │     to user         │  │  │     AI                  │  │
│  │  4. System stores   │  │  │  4. System returns  │  │  │  6. API returns response│  │
│  │     in Redis        │  │  │     session ID      │  │  │  7. Client displays     │  │
│  │  5. System returns  │  │  │  5. Client stores   │  │  │     message             │  │
│  │     token to client │  │  │     session ID      │  │  │  8. WebSocket updates   │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    PERFORMANCE OPTIMIZATION                            │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Database Optimization   │  Cache Optimization      │  Network Optimization           │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  Indexes            │  │  │  Redis Clustering   │  │  │  CDN for Static Content │  │
│  │  - user_id indexes  │  │  │  - Multiple Redis   │  │  │  - Global distribution  │  │
│  │  - session_id idx   │  │  │    instances        │  │  │  - Edge caching         │  │
│  │  - time-based idx   │  │  │  - Data sharding    │  │  │  - Bandwidth reduction  │  │
│  │  - composite idx    │  │  │  - Load balancing   │  │  │  - Latency reduction    │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
│                           │                           │                               │
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  Query Optimization │  │  │  Cache Strategies   │  │  │  Load Balancing         │  │
│  │  - Query planning   │  │  │  - Write-through    │  │  │  - Round-robin          │  │
│  │  - Query caching    │  │  │  - Write-behind     │  │  │  - Least connections    │  │
│  │  - Connection pool  │  │  │  - Cache-aside      │  │  │  - Health checks        │  │
│  │  - Prepared stmts   │  │  │  - TTL management   │  │  │  - Failover             │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    MONITORING AND LOGGING                              │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Session Metrics         │  Performance Metrics     │  Security Metrics               │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  Active Sessions    │  │  │  Response Times     │  │  │  Authentication Events  │  │
│  │  - Current count    │  │  │  - API response     │  │  │  - Login attempts       │  │
│  │  - Peak count       │  │  │  - DB query time    │  │  │  - Failed logins        │  │
│  │  - Average duration │  │  │  - Redis response   │  │  │  - Token validation     │  │
│  │  - Session growth   │  │  │  - WebSocket ping   │  │  │  - Permission violations│  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
│                           │                           │                               │
│  ┌─────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐  │
│  │  Message Metrics    │  │  │  Resource Usage     │  │  │  Data Access Logs       │  │
│  │  - Messages per sec │  │  │  - CPU usage        │  │  │  - Data access patterns │  │
│  │  - Message size     │  │  │  - Memory usage     │  │  │  - Cross-user access    │  │
│  │  - Message latency  │  │  │  - Disk usage       │  │  │  - Unauthorized access  │  │
│  │  - Message errors   │  │  │  - Network usage    │  │  │  - Data modification    │  │
│  └─────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘

This comprehensive diagram shows the complete Onyx sessions architecture, including data flow, security layers, performance optimization, and monitoring systems.
