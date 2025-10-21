# Vespa to pgvector Migration Guide

## 🎯 Why Migrate from Vespa to pgvector?

### Current State (Vespa)
- **Complex Setup**: Vespa requires dedicated infrastructure
- **Resource Heavy**: Memory and CPU intensive
- **Separate Database**: Additional system to maintain
- **Limited Integration**: Separate from main application data

### Target State (pgvector)
- **Simplified Architecture**: Single PostgreSQL database
- **Resource Efficient**: Lower memory footprint
- **Unified Data**: Vectors alongside relational data
- **Better Integration**: Native PostgreSQL features

## 📊 Architecture Comparison

### Before (Vespa)
```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Onyx API  │    │ PostgreSQL  │    │   Vespa     │
│             │───▶│             │    │             │
│ (FastAPI)   │    │ (Metadata)  │    │ (Vectors)   │
└─────────────┘    └─────────────┘    └─────────────┘
```

### After (pgvector)
```
┌─────────────┐    ┌─────────────────────────────┐
│   Onyx API  │    │      PostgreSQL            │
│             │───▶│  + pgvector extension     │
│ (FastAPI)   │    │  (Metadata + Vectors)     │
└─────────────┘    └─────────────────────────────┘
```

## 🔧 Migration Steps

### Step 1: Prepare PostgreSQL for pgvector

#### 1.1 Install pgvector Extension
```sql
-- Connect to your PostgreSQL database
CREATE EXTENSION IF NOT EXISTS vector;

-- Verify installation
SELECT * FROM pg_extension WHERE extname = 'vector';
```

#### 1.2 Create Vector Tables
```sql
-- Documents table with vector embeddings
CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT,
    content TEXT,
    metadata JSONB,
    embedding VECTOR(1536), -- Adjust dimension based on your model
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create indexes for vector similarity search
CREATE INDEX ON documents USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- Create indexes for metadata filtering
CREATE INDEX ON documents USING gin (metadata);
CREATE INDEX ON documents (created_at);
```

#### 1.3 Create Search Functions
```sql
-- Function for similarity search
CREATE OR REPLACE FUNCTION search_documents(
    query_embedding VECTOR(1536),
    similarity_threshold FLOAT DEFAULT 0.7,
    max_results INTEGER DEFAULT 10
)
RETURNS TABLE (
    id UUID,
    title TEXT,
    content TEXT,
    metadata JSONB,
    similarity FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.id,
        d.title,
        d.content,
        d.metadata,
        1 - (d.embedding <=> query_embedding) AS similarity
    FROM documents d
    WHERE 1 - (d.embedding <=> query_embedding) > similarity_threshold
    ORDER BY d.embedding <=> query_embedding
    LIMIT max_results;
END;
$$ LANGUAGE plpgsql;
```

### Step 2: Update Onyx Configuration

#### 2.1 Remove Vespa Configuration
```yaml
# Remove from ConfigMap
# VESPA_HOST: "vespa-0.vespa-service.onyx-infra.svc.cluster.local"
# VESPA_PORT: "19071"
```

#### 2.2 Add pgvector Configuration
```yaml
# Add to ConfigMap
VECTOR_DB_TYPE: "pgvector"
VECTOR_DB_HOST: "postgresql.onyx-infra.svc.cluster.local"
VECTOR_DB_PORT: "5432"
VECTOR_DB_NAME: "postgres"
VECTOR_DB_TABLE: "documents"
VECTOR_DB_EMBEDDING_DIMENSION: "1536"
```

### Step 3: Update Onyx Code

#### 3.1 Install Dependencies
```python
# Add to requirements.txt
psycopg2-binary==2.9.7
pgvector==0.2.4
```

#### 3.2 Create pgvector Client
```python
# onyx/vector_store/pgvector_client.py
import psycopg2
from pgvector.psycopg2 import register_vector
from typing import List, Dict, Any
import numpy as np

class PgVectorClient:
    def __init__(self, host: str, port: int, database: str, user: str, password: str):
        self.connection = psycopg2.connect(
            host=host,
            port=port,
            database=database,
            user=user,
            password=password
        )
        register_vector(self.connection)
    
    def search_similar(
        self, 
        query_embedding: List[float], 
        limit: int = 10, 
        threshold: float = 0.7
    ) -> List[Dict[str, Any]]:
        """Search for similar documents using cosine similarity"""
        cursor = self.connection.cursor()
        
        query = """
        SELECT id, title, content, metadata, 
               1 - (embedding <=> %s) AS similarity
        FROM documents 
        WHERE 1 - (embedding <=> %s) > %s
        ORDER BY embedding <=> %s
        LIMIT %s
        """
        
        cursor.execute(query, (query_embedding, query_embedding, threshold, query_embedding, limit))
        
        results = []
        for row in cursor.fetchall():
            results.append({
                'id': row[0],
                'title': row[1],
                'content': row[2],
                'metadata': row[3],
                'similarity': row[4]
            })
        
        cursor.close()
        return results
    
    def insert_document(
        self, 
        title: str, 
        content: str, 
        embedding: List[float], 
        metadata: Dict[str, Any] = None
    ) -> str:
        """Insert a new document with embedding"""
        cursor = self.connection.cursor()
        
        query = """
        INSERT INTO documents (title, content, embedding, metadata)
        VALUES (%s, %s, %s, %s)
        RETURNING id
        """
        
        cursor.execute(query, (title, content, embedding, metadata or {}))
        document_id = cursor.fetchone()[0]
        self.connection.commit()
        cursor.close()
        
        return document_id
```

#### 3.3 Update Onyx Search Logic
```python
# onyx/context/search/retrieval/search_runner.py
from onyx.vector_store.pgvector_client import PgVectorClient

class SearchRunner:
    def __init__(self):
        # Replace Vespa client with pgvector client
        self.vector_client = PgVectorClient(
            host=os.getenv('VECTOR_DB_HOST'),
            port=int(os.getenv('VECTOR_DB_PORT')),
            database=os.getenv('VECTOR_DB_NAME'),
            user=os.getenv('POSTGRES_USER'),
            password=os.getenv('POSTGRES_PASSWORD')
        )
    
    def search_documents(self, query_embedding: List[float], limit: int = 10):
        """Search for similar documents"""
        return self.vector_client.search_similar(
            query_embedding=query_embedding,
            limit=limit,
            threshold=0.7
        )
```

### Step 4: Data Migration

#### 4.1 Export Vespa Data
```python
# migration/export_vespa_data.py
import requests
import json

def export_vespa_documents():
    """Export all documents from Vespa"""
    url = "http://vespa-0.vespa-service.onyx-infra.svc.cluster.local:19071/search/"
    
    params = {
        "yql": "select * from sources * where true",
        "hits": 1000,  # Adjust based on your data size
        "format": "json"
    }
    
    response = requests.get(url, params=params)
    data = response.json()
    
    documents = []
    for hit in data.get('root', {}).get('children', []):
        fields = hit.get('fields', {})
        documents.append({
            'id': fields.get('id'),
            'title': fields.get('title'),
            'content': fields.get('content'),
            'metadata': fields.get('metadata', {}),
            'embedding': fields.get('embedding_vector')
        })
    
    return documents
```

#### 4.2 Import to pgvector
```python
# migration/import_to_pgvector.py
from onyx.vector_store.pgvector_client import PgVectorClient

def migrate_documents(documents):
    """Import documents to pgvector"""
    client = PgVectorClient(
        host="postgresql.onyx-infra.svc.cluster.local",
        port=5432,
        database="postgres",
        user="postgres",
        password="your_password"
    )
    
    for doc in documents:
        client.insert_document(
            title=doc['title'],
            content=doc['content'],
            embedding=doc['embedding'],
            metadata=doc['metadata']
        )
    
    print(f"Migrated {len(documents)} documents to pgvector")
```

### Step 5: Update Kubernetes Manifests

#### 5.1 Remove Vespa Deployment
```bash
# Remove Vespa StatefulSet and Service
kubectl delete -f manifests/03-vespa.yaml
```

#### 5.2 Update ConfigMap
```yaml
# manifests/05-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: onyx-config
data:
  # Remove Vespa configuration
  # VESPA_HOST: "vespa-0.vespa-service.onyx-infra.svc.cluster.local"
  
  # Add pgvector configuration
  VECTOR_DB_TYPE: "pgvector"
  VECTOR_DB_HOST: "postgresql.onyx-infra.svc.cluster.local"
  VECTOR_DB_PORT: "5432"
  VECTOR_DB_NAME: "postgres"
  VECTOR_DB_TABLE: "documents"
  VECTOR_DB_EMBEDDING_DIMENSION: "1536"
```

#### 5.3 Update PostgreSQL Deployment
```yaml
# Add pgvector extension to PostgreSQL init container
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-init-script
data:
  init.sql: |
    CREATE EXTENSION IF NOT EXISTS vector;
    -- Add your vector tables and functions here
```

## 🧪 Testing the Migration

### 1. Test Vector Search
```python
# test_pgvector_search.py
import numpy as np
from onyx.vector_store.pgvector_client import PgVectorClient

def test_vector_search():
    client = PgVectorClient(
        host="postgresql.onyx-infra.svc.cluster.local",
        port=5432,
        database="postgres",
        user="postgres",
        password="your_password"
    )
    
    # Test with a random embedding
    test_embedding = np.random.rand(1536).tolist()
    
    results = client.search_similar(
        query_embedding=test_embedding,
        limit=5,
        threshold=0.5
    )
    
    print(f"Found {len(results)} similar documents")
    for result in results:
        print(f"- {result['title']} (similarity: {result['similarity']:.3f})")
```

### 2. Performance Comparison
```python
# benchmark_vector_search.py
import time
import statistics

def benchmark_search(client, query_embedding, iterations=100):
    """Benchmark vector search performance"""
    times = []
    
    for _ in range(iterations):
        start_time = time.time()
        results = client.search_similar(query_embedding, limit=10)
        end_time = time.time()
        
        times.append(end_time - start_time)
    
    return {
        'mean': statistics.mean(times),
        'median': statistics.median(times),
        'min': min(times),
        'max': max(times),
        'std': statistics.stdev(times)
    }
```

## 📊 Benefits of Migration

### 1. **Simplified Architecture**
- Single database for all data
- Reduced infrastructure complexity
- Easier monitoring and maintenance

### 2. **Cost Reduction**
- No separate Vespa cluster needed
- Lower memory requirements
- Reduced operational overhead

### 3. **Better Integration**
- Vectors alongside relational data
- ACID transactions for vector operations
- Unified backup and recovery

### 4. **Performance**
- Faster queries for small to medium datasets
- Better caching with PostgreSQL
- Reduced network latency

## ⚠️ Considerations

### 1. **Scale Limitations**
- pgvector is optimized for moderate scale
- For very large datasets (>100M vectors), consider specialized solutions

### 2. **Index Performance**
- IVFFlat index requires tuning for optimal performance
- Consider HNSW index for better recall

### 3. **Memory Usage**
- Vector operations can be memory intensive
- Monitor PostgreSQL memory usage

## 🚀 Next Steps

1. **Deploy LiteLLM**: Follow `LITELLM-DEPLOYMENT-GUIDE.md`
2. **Configure Integration**: Use `ONYX-LITELLM-INTEGRATION.md`
3. **Test Performance**: Run benchmarks
4. **Monitor Migration**: Track metrics and performance
5. **Optimize**: Tune indexes and queries

## 📚 Additional Resources

- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [PostgreSQL Vector Operations](https://www.postgresql.org/docs/current/btree-gist.html)
- [Vector Similarity Search](https://docs.pinecone.io/docs/vector-similarity-search)
- [Onyx Vector Store](https://docs.onyx.ai/vector-store/)
