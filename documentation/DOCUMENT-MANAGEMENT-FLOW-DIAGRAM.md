# Document Management Flow Diagram

## 🎯 **Onyx Document Management Architecture**

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    ONYX DOCUMENT MANAGEMENT                             │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    USER INTERFACE LAYER                                 │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Regular Users                    │  Admins/Curators                                   │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────┐  │  ┌─────────────────────────────────────────────┐    │
│  │     Project Files           │  │  │           Document Sets                     │    │
│  │  ┌─────────────────────────┐│  │  │  ┌─────────────────────────────────────────┐│    │
│  │  │  Upload Files           ││  │  │  │  Create/Edit/Delete Sets               ││    │
│  │  │  Remove from Project    ││  │  │  │  Manage Permissions                    ││    │
│  │  │  Delete Files           ││  │  │  │  View Contents                         ││    │
│  │  └─────────────────────────┘│  │  │  └─────────────────────────────────────────┘│    │
│  └─────────────────────────────┘  │  └─────────────────────────────────────────────┘    │
│                                   │                                                    │
│  ┌─────────────────────────────┐  │  ┌─────────────────────────────────────────────┐    │
│  │     Personal Files          │  │  │              Connectors                     │    │
│  │  ┌─────────────────────────┐│  │  │  ┌─────────────────────────────────────────┐│    │
│  │  │  View All Files         ││  │  │  │  Add/Edit/Delete Connectors            ││    │
│  │  │  Delete Files           ││  │  │  │  Manage Sync Settings                  ││    │
│  │  │  Manage Permissions     ││  │  │  │  View Sync Status                      ││    │
│  │  └─────────────────────────┘│  │  │  └─────────────────────────────────────────┘│    │
│  └─────────────────────────────┘  │  └─────────────────────────────────────────────┘    │
│                                   │                                                    │
│                                   │  ┌─────────────────────────────────────────────┐    │
│                                   │  │           Document Explorer                 │    │
│                                   │  │  ┌─────────────────────────────────────────┐│    │
│                                   │  │  │  Search Documents                      ││    │
│                                   │  │  │  View Document Details                 ││    │
│                                   │  │  │  Delete Individual Documents           ││    │
│                                   │  │  │  Manage Visibility                     ││    │
│                                   │  │  └─────────────────────────────────────────┘│    │
│                                   │  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    API LAYER                                            │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  User APIs                    │  Admin APIs                                             │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────┐  │  ┌─────────────────────────────────────────────────┐    │
│  │  DELETE /file/{file_id} │  │  │  DELETE /admin/document-set/{id}               │    │
│  │  - Delete user files    │  │  │  - Delete document sets                       │    │
│  │  - Remove from projects │  │  │  - Schedule for deletion                     │    │
│  └─────────────────────────┘  │  └─────────────────────────────────────────────────┘    │
│                               │                                                         │
│  ┌─────────────────────────┐  │  ┌─────────────────────────────────────────────────┐    │
│  │  DELETE /project/{id}   │  │  │  DELETE /admin/connector/{id}                 │    │
│  │  - Delete projects      │  │  │  - Delete connectors                         │    │
│  │  - Remove file links    │  │  │  - Delete all connector documents           │    │
│  └─────────────────────────┘  │  └─────────────────────────────────────────────────┘    │
│                               │                                                         │
│                               │  ┌─────────────────────────────────────────────────┐    │
│                               │  │  DELETE /admin/document/{id}                  │    │
│                               │  │  - Delete individual documents                │    │
│                               │  │  - Remove from search index                  │    │
│                               │  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    DATABASE LAYER                                       │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Document Storage          │  Metadata Storage        │  Search Index                  │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐│
│  │  User Files            │  │  │  Document Metadata  │  │  │  Vector Embeddings      ││
│  │  - File content        │  │  │  - Document info    │  │  │  - Search vectors       ││
│  │  - File metadata       │  │  │  - User associations│  │  │  - Chunk vectors        ││
│  │  - Project links       │  │  │  - Permission data  │  │  │  - Search metadata      ││
│  └─────────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘│
│                               │                           │                             │
│  ┌─────────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐│
│  │  Connector Documents   │  │  │  Document Sets      │  │  │  Document Chunks        ││
│  │  - Synced content      │  │  │  - Set definitions  │  │  │  - Text chunks          ││
│  │  - Sync metadata       │  │  │  - Document lists   │  │  │  - Chunk metadata       ││
│  │  - Source references   │  │  │  - Permission data  │  │  │  - Chunk associations   ││
│  └─────────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    DELETION PROCESS                                     │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  User Deletion Request    │  Admin Deletion Request   │  System Deletion Process      │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────┐  │  ┌─────────────────────┐  │  ┌─────────────────────────┐│
│  │  1. User clicks delete  │  │  │  1. Admin clicks    │  │  │  1. Mark for deletion   ││
│  │  2. Confirm deletion    │  │  │     delete          │  │  │  2. Remove from UI      ││
│  │  3. File removed from   │  │  │  2. Confirm deletion│  │  │  3. Update search index ││
│  │     project/storage     │  │  │  3. Document set/   │  │  │  4. Clean up metadata   ││
│  │  4. Deletion logged     │  │  │     connector       │  │  │  5. Free storage space  ││
│  │                         │  │  │     scheduled for   │  │  │  6. Log deletion        ││
│  │                         │  │  │     deletion        │  │  │                         ││
│  └─────────────────────────┘  │  └─────────────────────┘  │  └─────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    PERMISSION MATRIX                                    │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  User Type        │  Own Files  │  Project Files  │  Document Sets  │  Connectors      │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  Regular User     │  ✅ Delete   │  ✅ Remove      │  ❌ No Access   │  ❌ No Access    │
│  Curator          │  ✅ Delete   │  ✅ Remove      │  ✅ Delete      │  ❌ No Access    │
│  Admin            │  ✅ Delete   │  ✅ Remove      │  ✅ Delete      │  ✅ Delete       │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    DELETION TYPES                                       │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Deletion Type    │  Scope                    │  Recovery  │  Background Processing    │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  User File        │  Single file              │  ❌ No     │  ✅ Yes (immediate)       │
│  Project File     │  File from project        │  ❌ No     │  ✅ Yes (immediate)       │
│  Document Set     │  All documents in set     │  ❌ No     │  ✅ Yes (scheduled)       │
│  Connector        │  All connector documents  │  ❌ No     │  ✅ Yes (scheduled)       │
│  Individual Doc   │  Single document          │  ❌ No     │  ✅ Yes (scheduled)       │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    AUDIT AND LOGGING                                    │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Log Type          │  Information Captured        │  Retention Period  │  Access Level  │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  Deletion Log      │  - User who deleted          │  1 year            │  Admin only    │
│                    │  - What was deleted          │                    │                │
│                    │  - When deletion occurred    │                    │                │
│                    │  - Deletion method           │                    │                │
│  Access Log        │  - Who accessed document     │  6 months          │  Admin only    │
│                    │  - When accessed             │                    │                │
│                    │  - Access method             │                    │                │
│  System Log        │  - Background processing     │  3 months          │  Admin only    │
│                    │  - Error messages            │                    │                │
│                    │  - Performance metrics       │                    │                │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    TROUBLESHOOTING FLOW                                 │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  Issue                    │  Check First              │  Solution                      │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  Cannot delete file       │  User permissions         │  Check user role and access    │
│  Document still in search │  Background processing    │  Wait for index update         │
│  Cannot delete set        │  Set dependencies         │  Remove from personas/connectors│
│  File still takes space   │  Cleanup process          │  Wait for storage cleanup      │
│  Deletion failed          │  System logs              │  Check error messages          │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    BEST PRACTICES                                       │
└─────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  For Users:               │  For Admins:                                              │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  ✅ Delete unused files   │  ✅ Regular cleanup of document sets                      │
│  ✅ Organize projects     │  ✅ Monitor storage usage                                 │
│  ✅ Use descriptive names │  ✅ Review deletion logs                                  │
│  ✅ Remove old files      │  ✅ Clean up unused connectors                            │
│  ❌ Don't delete shared   │  ❌ Don't delete active document sets                     │
│      files without asking │  ❌ Don't delete connectors in use                       │
└─────────────────────────────────────────────────────────────────────────────────────────┘

This diagram shows the complete document management flow in Onyx, including user interfaces, API endpoints, database layers, deletion processes, permissions, and troubleshooting steps.
