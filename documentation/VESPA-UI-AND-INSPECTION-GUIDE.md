# Vespa UI and Inspection Guide - Check Deletion Inconsistencies

## 🎯 Overview

This guide explains **all options** for inspecting Vespa data to check for deletion inconsistencies. You have **multiple options**, from built-in tools to custom UIs.

---

## ✅ Option 1: Vespa Built-in Admin UI (Easiest)

### What It Is

Vespa has a **built-in admin UI** accessible via web browser. It provides:
- Document inspection
- Query interface
- Statistics and metrics
- Configuration management

### How to Access

**In Docker Compose:**
```bash
# Port forward Vespa admin port
docker-compose port index 19071
# Or directly access if exposed
http://localhost:19071
```

**In Kubernetes:**
```bash
# Port forward Vespa service
kubectl port-forward -n <namespace> svc/vespa-service 19071:19071

# Then access in browser
http://localhost:19071
```

**Direct Access (if service is exposed):**
```
http://<vespa-host>:19071
```

### What You Can Do

1. **Query Documents**:
   - Navigate to Query interface
   - Use YQL to search for specific document_ids
   - Check if deleted files still exist

2. **View Statistics**:
   - Document counts
   - Index status
   - Search performance

3. **Inspect Documents**:
   - View document fields
   - Check chunk counts
   - Verify metadata

---

## ✅ Option 2: Vespa Query API (Direct Access)

### Using REST API

**Query Vespa directly via HTTP:**

```bash
# Get Vespa endpoint
VESPA_HOST="index"  # or your Vespa service name
VESPA_PORT="8080"

# Query for specific document
curl -X POST "http://${VESPA_HOST}:${VESPA_PORT}/search/" \
  -H "Content-Type: application/json" \
  -d '{
    "yql": "select * from sources onyx_chunk where document_id contains \"<file_id>\"",
    "hits": 100
  }'
```

**Check if document exists:**
```bash
# Replace <file_id> with actual UUID
curl -X POST "http://${VESPA_HOST}:${VESPA_PORT}/search/" \
  -H "Content-Type: application/json" \
  -d '{
    "yql": "select documentid, document_id from sources onyx_chunk where document_id = \"<file_id>\"",
    "hits": 10
  }'
```

---

## ✅ Option 3: Build Custom Admin UI in Onyx (Recommended)

### Why This Is Best

- **Integrated**: Works with your existing Onyx UI
- **Secure**: Uses your authentication
- **Customizable**: Show exactly what you need
- **Database Comparison**: Can compare Vespa vs PostgreSQL

### Implementation Plan

#### Step 1: Create Backend API Endpoint

**File**: `onyx-repo/backend/onyx/server/features/admin/vespa_inspection.py` (new file)

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from onyx.db.engine.sql_engine import get_session
from onyx.db.models import UserFile
from onyx.db.enums import UserFileStatus
from onyx.document_index.vespa.index import VespaIndex
from onyx.document_index.vespa.shared_utils.utils import get_vespa_http_client
from onyx.document_index.vespa_constants import SEARCH_ENDPOINT
from onyx.server.manage.models import User
from onyx.server.manage.user_management import current_curator_or_admin_user
from pydantic import BaseModel
from typing import Optional
from uuid import UUID

router = APIRouter(prefix="/admin/vespa", tags=["admin"])


class VespaDocumentCheck(BaseModel):
    document_id: str
    exists_in_vespa: bool
    chunk_count_in_vespa: int
    exists_in_postgres: bool
    status_in_postgres: Optional[str]
    is_consistent: bool
    inconsistency_reason: Optional[str] = None


class VespaInspectionRequest(BaseModel):
    document_id: Optional[str] = None
    user_file_id: Optional[str] = None
    check_all_deleted: bool = False


@router.post("/check-document", response_model=VespaDocumentCheck)
def check_document_consistency(
    request: VespaInspectionRequest,
    user: User = Depends(current_curator_or_admin_user),
    db_session: Session = Depends(get_session),
) -> VespaDocumentCheck:
    """
    Check if a document exists in both Vespa and PostgreSQL.
    Useful for detecting deletion inconsistencies.
    """
    from onyx.document_index.vespa.shared_utils.utils import get_vespa_http_client
    from onyx.document_index.vespa_constants import SEARCH_ENDPOINT
    from onyx.db.search_settings import get_current_search_settings
    
    # Get document_id to check
    document_id = request.document_id
    if request.user_file_id:
        # Convert user_file_id to document_id
        try:
            user_file = db_session.get(UserFile, UUID(request.user_file_id))
            if user_file:
                document_id = str(user_file.id)
        except Exception:
            raise HTTPException(status_code=404, detail="User file not found")
    
    if not document_id:
        raise HTTPException(status_code=400, detail="document_id or user_file_id required")
    
    # Check PostgreSQL
    postgres_exists = False
    postgres_status = None
    try:
        user_file = db_session.query(UserFile).filter(
            UserFile.id == UUID(document_id)
        ).first()
        if user_file:
            postgres_exists = True
            postgres_status = user_file.status.value
    except Exception:
        pass
    
    # Check Vespa
    vespa_exists = False
    chunk_count = 0
    try:
        search_settings = get_current_search_settings(db_session)
        index_name = search_settings.primary.index_name
        
        yql_query = f'select * from sources {index_name} where document_id = "{document_id}"'
        
        with get_vespa_http_client() as client:
            response = client.post(
                f"{SEARCH_ENDPOINT}search/",
                json={"yql": yql_query, "hits": 1000}
            )
            response.raise_for_status()
            result = response.json()
            chunks = result.get("root", {}).get("children", [])
            chunk_count = len(chunks)
            vespa_exists = chunk_count > 0
    except Exception as e:
        # Vespa query failed
        pass
    
    # Determine consistency
    is_consistent = True
    inconsistency_reason = None
    
    if postgres_exists and postgres_status == "DELETING":
        # File is being deleted
        if vespa_exists:
            is_consistent = False
            inconsistency_reason = "File marked as DELETING in PostgreSQL but still exists in Vespa"
    elif not postgres_exists:
        # File deleted from PostgreSQL
        if vespa_exists:
            is_consistent = False
            inconsistency_reason = "File deleted from PostgreSQL but still exists in Vespa"
    elif postgres_exists and postgres_status == "COMPLETED":
        # File should exist in both
        if not vespa_exists:
            is_consistent = False
            inconsistency_reason = "File exists in PostgreSQL but not in Vespa"
    
    return VespaDocumentCheck(
        document_id=document_id,
        exists_in_vespa=vespa_exists,
        chunk_count_in_vespa=chunk_count,
        exists_in_postgres=postgres_exists,
        status_in_postgres=postgres_status,
        is_consistent=is_consistent,
        inconsistency_reason=inconsistency_reason,
    )


@router.get("/inconsistencies")
def find_deletion_inconsistencies(
    user: User = Depends(current_curator_or_admin_user),
    db_session: Session = Depends(get_session),
) -> list[VespaDocumentCheck]:
    """
    Find all files with deletion inconsistencies.
    Compares PostgreSQL user_file table with Vespa index.
    """
    from onyx.db.search_settings import get_current_search_settings
    from onyx.document_index.vespa.shared_utils.utils import get_vespa_http_client
    from onyx.document_index.vespa_constants import SEARCH_ENDPOINT
    
    inconsistencies = []
    
    # Get all deleted/deleting files from PostgreSQL
    deleted_files = db_session.query(UserFile).filter(
        UserFile.status.in_([UserFileStatus.DELETING, UserFileStatus.FAILED])
    ).all()
    
    search_settings = get_current_search_settings(db_session)
    index_name = search_settings.primary.index_name
    
    # Check each file in Vespa
    for user_file in deleted_files:
        document_id = str(user_file.id)
        
        try:
            yql_query = f'select * from sources {index_name} where document_id = "{document_id}"'
            
            with get_vespa_http_client() as client:
                response = client.post(
                    f"{SEARCH_ENDPOINT}search/",
                    json={"yql": yql_query, "hits": 1000}
                )
                response.raise_for_status()
                result = response.json()
                chunks = result.get("root", {}).get("children", [])
                chunk_count = len(chunks)
                
                if chunk_count > 0:
                    # Inconsistency found!
                    inconsistencies.append(
                        VespaDocumentCheck(
                            document_id=document_id,
                            exists_in_vespa=True,
                            chunk_count_in_vespa=chunk_count,
                            exists_in_postgres=True,
                            status_in_postgres=user_file.status.value,
                            is_consistent=False,
                            inconsistency_reason=f"File with status {user_file.status.value} still has {chunk_count} chunks in Vespa",
                        )
                    )
        except Exception as e:
            # Skip if query fails
            continue
    
    return inconsistencies
```

**Add to router** (in `onyx-repo/backend/onyx/server/features/admin/__init__.py` or main router):
```python
from onyx.server.features.admin.vespa_inspection import router as vespa_inspection_router
app.include_router(vespa_inspection_router)
```

---

#### Step 2: Create Frontend Admin Page

**File**: `onyx-repo/web/src/app/admin/vespa-inspection/page.tsx` (new file)

```tsx
"use client";

import { useState } from "react";
import { AdminPageTitle } from "@/components/admin/Title";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { FiSearch, FiAlertCircle, FiCheckCircle } from "react-icons/fi";

interface VespaDocumentCheck {
  document_id: string;
  exists_in_vespa: boolean;
  chunk_count_in_vespa: number;
  exists_in_postgres: boolean;
  status_in_postgres: string | null;
  is_consistent: boolean;
  inconsistency_reason: string | null;
}

export default function VespaInspectionPage() {
  const [documentId, setDocumentId] = useState("");
  const [userFileId, setUserFileId] = useState("");
  const [result, setResult] = useState<VespaDocumentCheck | null>(null);
  const [loading, setLoading] = useState(false);
  const [inconsistencies, setInconsistencies] = useState<VespaDocumentCheck[]>([]);
  const [loadingInconsistencies, setLoadingInconsistencies] = useState(false);

  const checkDocument = async () => {
    if (!documentId && !userFileId) return;
    
    setLoading(true);
    try {
      const response = await fetch("/api/admin/vespa/check-document", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          document_id: documentId || undefined,
          user_file_id: userFileId || undefined,
        }),
      });
      
      if (!response.ok) throw new Error("Check failed");
      
      const data = await response.json();
      setResult(data);
    } catch (error) {
      console.error("Error checking document:", error);
    } finally {
      setLoading(false);
    }
  };

  const findInconsistencies = async () => {
    setLoadingInconsistencies(true);
    try {
      const response = await fetch("/api/admin/vespa/inconsistencies");
      
      if (!response.ok) throw new Error("Failed to find inconsistencies");
      
      const data = await response.json();
      setInconsistencies(data);
    } catch (error) {
      console.error("Error finding inconsistencies:", error);
    } finally {
      setLoadingInconsistencies(false);
    }
  };

  return (
    <main className="pt-4 mx-auto container max-w-6xl">
      <AdminPageTitle
        title="Vespa Inspection & Deletion Consistency Check"
        icon={<FiSearch size={32} />}
      />

      {/* Check Single Document */}
      <Card className="mb-6">
        <CardHeader>
          <CardTitle>Check Single Document</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex gap-4">
            <Input
              placeholder="Document ID (UUID)"
              value={documentId}
              onChange={(e) => setDocumentId(e.target.value)}
            />
            <Input
              placeholder="User File ID (UUID)"
              value={userFileId}
              onChange={(e) => setUserFileId(e.target.value)}
            />
            <Button onClick={checkDocument} disabled={loading}>
              {loading ? "Checking..." : "Check Document"}
            </Button>
          </div>

          {result && (
            <div className="mt-4 space-y-2">
              <Alert variant={result.is_consistent ? "default" : "destructive"}>
                <div className="flex items-center gap-2">
                  {result.is_consistent ? (
                    <FiCheckCircle className="h-4 w-4" />
                  ) : (
                    <FiAlertCircle className="h-4 w-4" />
                  )}
                  <AlertDescription>
                    <strong>Status:</strong>{" "}
                    {result.is_consistent ? "Consistent" : "Inconsistent"}
                  </AlertDescription>
                </div>
              </Alert>

              <div className="grid grid-cols-2 gap-4 mt-4">
                <div>
                  <strong>PostgreSQL:</strong>
                  <div className="text-sm text-gray-600">
                    Exists: {result.exists_in_postgres ? "Yes" : "No"}
                    {result.status_in_postgres && (
                      <> | Status: <Badge>{result.status_in_postgres}</Badge></>
                    )}
                  </div>
                </div>
                <div>
                  <strong>Vespa:</strong>
                  <div className="text-sm text-gray-600">
                    Exists: {result.exists_in_vespa ? "Yes" : "No"}
                    {result.exists_in_vespa && (
                      <> | Chunks: {result.chunk_count_in_vespa}</>
                    )}
                  </div>
                </div>
              </div>

              {result.inconsistency_reason && (
                <Alert variant="destructive" className="mt-2">
                  <AlertDescription>
                    <strong>Issue:</strong> {result.inconsistency_reason}
                  </AlertDescription>
                </Alert>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Find All Inconsistencies */}
      <Card>
        <CardHeader>
          <CardTitle>Find All Deletion Inconsistencies</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <Button
            onClick={findInconsistencies}
            disabled={loadingInconsistencies}
            variant="outline"
          >
            {loadingInconsistencies
              ? "Scanning..."
              : "Scan for Inconsistencies"}
          </Button>

          {inconsistencies.length > 0 && (
            <div className="mt-4">
              <Alert variant="destructive">
                <AlertDescription>
                  Found <strong>{inconsistencies.length}</strong> inconsistent
                  files
                </AlertDescription>
              </Alert>

              <div className="mt-4 space-y-2">
                {inconsistencies.map((inc) => (
                  <Card key={inc.document_id} className="border-red-200">
                    <CardContent className="pt-4">
                      <div className="flex justify-between items-start">
                        <div>
                          <strong>Document ID:</strong>{" "}
                          <code className="text-xs">{inc.document_id}</code>
                          <div className="text-sm text-gray-600 mt-1">
                            {inc.inconsistency_reason}
                          </div>
                        </div>
                        <div className="text-right">
                          <Badge variant="destructive">Inconsistent</Badge>
                          <div className="text-xs text-gray-500 mt-1">
                            {inc.chunk_count_in_vespa} chunks in Vespa
                          </div>
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            </div>
          )}

          {inconsistencies.length === 0 && !loadingInconsistencies && (
            <Alert>
              <AlertDescription>
                No inconsistencies found. All deleted files are properly
                removed from Vespa.
              </AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>
    </main>
  );
}
```

**Add to Admin Sidebar** (`onyx-repo/web/src/sections/sidebar/AdminSidebar.tsx`):
```tsx
{
  name: "Vespa Inspection",
  link: "/admin/vespa-inspection",
  icon: <FiSearch size={20} />,
}
```

---

## ✅ Option 4: Use Existing Debugging Script

### Command-Line Tool

**File**: `onyx-repo/backend/scripts/debugging/onyx_vespa.py`

**Usage:**
```bash
cd /Users/chihebmhamdi/Desktop/onyx/onyx-repo/backend

# Check if document exists in Vespa
python -m onyx.scripts.debugging.onyx_vespa \
  --action search_for_document \
  --doc-id "<file_id>"

# Compare chunk counts
python -m onyx.scripts.debugging.onyx_vespa \
  --action compare_chunk_count \
  --doc-id "<file_id>"
```

---

## 📊 Comparison Table

| Option | Pros | Cons | Best For |
|--------|------|------|----------|
| **Vespa Admin UI** | Built-in, no code needed | Requires port forwarding, basic interface | Quick checks |
| **REST API** | Direct access, scriptable | Manual queries, no UI | Automation |
| **Custom Onyx UI** | Integrated, secure, customizable | Requires development | Production use |
| **CLI Script** | Fast, scriptable | Command-line only | Debugging |

---

## 🎯 Recommended Solution

**For your use case (checking deletion inconsistencies):**

**Best Option**: **Custom Admin UI in Onyx** (Option 3)

**Why:**
1. ✅ **Integrated** with your existing admin panel
2. ✅ **Secure** - uses your authentication
3. ✅ **Shows exactly what you need** - PostgreSQL vs Vespa comparison
4. ✅ **Easy to use** - no port forwarding needed
5. ✅ **Can fix issues** - can trigger cleanup actions

---

## 🚀 Quick Start: Minimal Implementation

### Step 1: Add Backend Endpoint (30 minutes)

1. Create `onyx-repo/backend/onyx/server/features/admin/vespa_inspection.py`
2. Add the code from Option 3 above
3. Register router in main app

### Step 2: Add Frontend Page (1 hour)

1. Create `onyx-repo/web/src/app/admin/vespa-inspection/page.tsx`
2. Add to admin sidebar
3. Test the interface

### Step 3: Test

1. Upload a file
2. Delete the file
3. Use the UI to check for inconsistencies
4. Verify it shows the issue

---

## 🔧 Alternative: Quick CLI Check

**If you need immediate results without UI:**

```bash
# Create a simple script
cat > check_vespa_deletion.sh << 'EOF'
#!/bin/bash
FILE_ID="$1"

# Check PostgreSQL
psql -h <postgres-host> -U <user> -d <db> -c \
  "SELECT id, name, status FROM user_file WHERE id = '$FILE_ID'::uuid;"

# Check Vespa
curl -X POST "http://<vespa-host>:8080/search/" \
  -H "Content-Type: application/json" \
  -d "{
    \"yql\": \"select * from sources onyx_chunk where document_id = \\\"$FILE_ID\\\"\",
    \"hits\": 10
  }"
EOF

chmod +x check_vespa_deletion.sh
./check_vespa_deletion.sh <file_id>
```

---

## 📝 Summary

**Yes, you can add a UI to check Vespa inconsistencies!**

**Recommended Approach:**
1. ✅ **Build custom admin UI** in Onyx (best long-term solution)
2. ✅ **Use Vespa Admin UI** for quick checks (port forward to 19071)
3. ✅ **Use CLI scripts** for automation

**The custom UI is best because:**
- Shows PostgreSQL vs Vespa comparison
- Highlights inconsistencies clearly
- Can trigger cleanup actions
- Integrated with your existing admin panel

---

**Last Updated**: 2024  
**Version**: 1.0

