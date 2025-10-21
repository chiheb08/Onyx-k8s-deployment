# Onyx + LiteLLM Integration Guide

## 🎯 Overview

This guide shows how to integrate LiteLLM proxy with Onyx to provide a unified LLM interface, cost optimization, and improved reliability.

## 🏗️ Integration Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Onyx UI       │    │  LiteLLM Proxy   │    │  LLM Providers  │
│   (Next.js)     │───▶│  (Unified API)   │───▶│  OpenAI, etc.   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │
         │                        │
         ▼                        ▼
┌─────────────────┐    ┌──────────────────┐
│   Onyx API      │    │   PostgreSQL     │
│   (FastAPI)     │    │   + pgvector    │
└─────────────────┘    └──────────────────┘
```

## 🔧 Step 1: Deploy LiteLLM Proxy

### 1.1 Create LiteLLM Deployment
```yaml
# litellm-integration/manifests/litellm-proxy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: litellm-proxy
  labels:
    app: litellm-proxy
spec:
  replicas: 2
  selector:
    matchLabels:
      app: litellm-proxy
  template:
    metadata:
      labels:
        app: litellm-proxy
    spec:
      containers:
        - name: litellm-proxy
          image: ghcr.io/berriai/litellm:main-latest
          ports:
            - name: http
              containerPort: 4000
              protocol: TCP
          env:
            - name: LITELLM_LOG_LEVEL
              value: "INFO"
            - name: LITELLM_MASTER_KEY
              valueFrom:
                secretKeyRef:
                  name: litellm-secret
                  key: master-key
          command:
            - litellm
            - --config
            - /app/config.yaml
          volumeMounts:
            - name: litellm-config
              mountPath: /app/config.yaml
              subPath: config.yaml
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: 1000m
              memory: 2Gi
          livenessProbe:
            httpGet:
              path: /health
              port: 4000
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 4000
            initialDelaySeconds: 10
            periodSeconds: 5
      volumes:
        - name: litellm-config
          configMap:
            name: litellm-config
---
apiVersion: v1
kind: Service
metadata:
  name: litellm-proxy
  labels:
    app: litellm-proxy
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 4000
      targetPort: 4000
      protocol: TCP
  selector:
    app: litellm-proxy
```

### 1.2 Create LiteLLM Configuration
```yaml
# litellm-integration/manifests/litellm-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: litellm-config
data:
  config.yaml: |
    model_list:
      # OpenAI Models
      - model_name: gpt-4
        litellm_params:
          model: gpt-4
          api_key: ${OPENAI_API_KEY}
      - model_name: gpt-3.5-turbo
        litellm_params:
          model: gpt-3.5-turbo
          api_key: ${OPENAI_API_KEY}
      
      # Anthropic Models
      - model_name: claude-3-sonnet
        litellm_params:
          model: claude-3-sonnet-20240229
          api_key: ${ANTHROPIC_API_KEY}
      
      # Local Models (if using vLLM)
      - model_name: llama-2-7b
        litellm_params:
          model: vllm/llama-2-7b-chat
          api_base: http://vllm-server:8000
    
    # Routing rules for Onyx
    routing:
      - condition: "user_tier == 'premium'"
        model: "gpt-4"
      - condition: "user_tier == 'basic'"
        model: "gpt-3.5-turbo"
      - condition: "task_type == 'summarization'"
        model: "claude-3-sonnet"
    
    # Caching configuration
    cache:
      type: "redis"
      host: "redis.onyx-infra.svc.cluster.local"
      port: 6379
      password: "${REDIS_PASSWORD}"
      ttl: 3600  # 1 hour
    
    # Rate limiting
    rate_limits:
      - model: "gpt-4"
        rpm: 60  # requests per minute
        tpm: 150000  # tokens per minute
      - model: "gpt-3.5-turbo"
        rpm: 300
        tpm: 300000
    
    # Fallback configuration
    fallbacks:
      - model: "gpt-4"
        fallback: "gpt-3.5-turbo"
        fallback: "claude-3-sonnet"
      - model: "gpt-3.5-turbo"
        fallback: "claude-3-sonnet"
---
apiVersion: v1
kind: Secret
metadata:
  name: litellm-secret
type: Opaque
data:
  master-key: bGl0ZWxsbS1tYXN0ZXIta2V5  # base64 encoded
  openai-api-key: <base64-encoded-openai-key>
  anthropic-api-key: <base64-encoded-anthropic-key>
```

## 🔧 Step 2: Update Onyx Configuration

### 2.1 Update Onyx ConfigMap
```yaml
# manifests/05-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: onyx-config
data:
  # ... existing configuration ...
  
  # ============================================================================
  # LITELLM PROXY CONFIGURATION
  # ============================================================================
  # LiteLLM proxy provides unified LLM interface
  # - Single endpoint for multiple LLM providers
  # - Automatic failover and load balancing
  # - Cost optimization through routing
  # - Response caching to reduce API costs
  # 
  # Used by: API Server (for LLM requests)
  # ============================================================================
  LITELLM_PROXY_URL: "http://litellm-proxy.onyx-infra.svc.cluster.local:4000"
  LITELLM_PROXY_API_KEY: "litellm-master-key"  # From secret
  
  # ============================================================================
  # LLM MODEL CONFIGURATION
  # ============================================================================
  # Primary model for Onyx operations
  # - Used for question answering
  # - Document analysis
  # - Chat interactions
  # 
  # LiteLLM will handle routing to appropriate model based on:
  # - User tier (premium vs basic)
  # - Task complexity
  # - Cost optimization rules
  # ============================================================================
  LLM_MODEL: "gpt-4"  # Primary model (LiteLLM will route appropriately)
  LLM_TEMPERATURE: "0.7"
  LLM_MAX_TOKENS: "4000"
  
  # ============================================================================
  # VECTOR DATABASE CONFIGURATION (pgvector)
  # ============================================================================
  # PostgreSQL with pgvector extension for vector operations
  # - Replaces Vespa for vector storage
  # - Unified database for metadata and vectors
  # - Better integration with Onyx data model
  # 
  # Used by: API Server (for vector search)
  # ============================================================================
  VECTOR_DB_TYPE: "pgvector"
  VECTOR_DB_HOST: "postgresql.onyx-infra.svc.cluster.local"
  VECTOR_DB_PORT: "5432"
  VECTOR_DB_NAME: "postgres"
  VECTOR_DB_TABLE: "documents"
  VECTOR_DB_EMBEDDING_DIMENSION: "1536"
```

### 2.2 Update API Server Deployment
```yaml
# manifests/07-api-server.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
spec:
  template:
    spec:
      containers:
        - name: api-server
          env:
            # ... existing environment variables ...
            
            # LiteLLM proxy configuration
            - name: LITELLM_PROXY_URL
              valueFrom:
                configMapKeyRef:
                  name: onyx-config
                  key: LITELLM_PROXY_URL
            - name: LITELLM_PROXY_API_KEY
              valueFrom:
                secretKeyRef:
                  name: litellm-secret
                  key: master-key
            
            # LLM configuration
            - name: LLM_MODEL
              valueFrom:
                configMapKeyRef:
                  name: onyx-config
                  key: LLM_MODEL
            - name: LLM_TEMPERATURE
              valueFrom:
                configMapKeyRef:
                  name: onyx-config
                  key: LLM_TEMPERATURE
            - name: LLM_MAX_TOKENS
              valueFrom:
                configMapKeyRef:
                  name: onyx-config
                  key: LLM_MAX_TOKENS
```

## 🔧 Step 3: Update Onyx Code

### 3.1 Create LiteLLM Client
```python
# onyx/llm/litellm_client.py
import httpx
import json
from typing import List, Dict, Any, Optional
import os

class LiteLLMClient:
    def __init__(self):
        self.base_url = os.getenv('LITELLM_PROXY_URL')
        self.api_key = os.getenv('LITELLM_PROXY_API_KEY')
        self.default_model = os.getenv('LLM_MODEL', 'gpt-4')
        self.temperature = float(os.getenv('LLM_TEMPERATURE', '0.7'))
        self.max_tokens = int(os.getenv('LLM_MAX_TOKENS', '4000'))
    
    async def chat_completion(
        self,
        messages: List[Dict[str, str]],
        model: Optional[str] = None,
        temperature: Optional[float] = None,
        max_tokens: Optional[int] = None,
        **kwargs
    ) -> Dict[str, Any]:
        """Send chat completion request to LiteLLM proxy"""
        
        payload = {
            "model": model or self.default_model,
            "messages": messages,
            "temperature": temperature or self.temperature,
            "max_tokens": max_tokens or self.max_tokens,
            **kwargs
        }
        
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.base_url}/chat/completions",
                json=payload,
                headers=headers,
                timeout=60.0
            )
            response.raise_for_status()
            return response.json()
    
    async def generate_embeddings(
        self,
        input_text: str,
        model: str = "text-embedding-ada-002"
    ) -> List[float]:
        """Generate embeddings using LiteLLM proxy"""
        
        payload = {
            "model": model,
            "input": input_text
        }
        
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.base_url}/embeddings",
                json=payload,
                headers=headers,
                timeout=30.0
            )
            response.raise_for_status()
            result = response.json()
            return result['data'][0]['embedding']
```

### 3.2 Update Onyx LLM Integration
```python
# onyx/llm/llm_provider.py
from onyx.llm.litellm_client import LiteLLMClient
from typing import List, Dict, Any

class LLMProvider:
    def __init__(self):
        self.client = LiteLLMClient()
    
    async def answer_question(
        self,
        question: str,
        context: List[Dict[str, Any]],
        user_tier: str = "basic"
    ) -> str:
        """Answer a question using LiteLLM with context"""
        
        # Build context from retrieved documents
        context_text = "\n\n".join([
            f"Document: {doc.get('title', 'Unknown')}\n{doc.get('content', '')}"
            for doc in context
        ])
        
        messages = [
            {
                "role": "system",
                "content": f"""You are a helpful assistant that answers questions based on the provided context.
                
                Context:
                {context_text}
                
                Please answer the user's question based on the context above. If the context doesn't contain enough information, say so."""
            },
            {
                "role": "user",
                "content": question
            }
        ]
        
        # Route to appropriate model based on user tier
        model = "gpt-4" if user_tier == "premium" else "gpt-3.5-turbo"
        
        response = await self.client.chat_completion(
            messages=messages,
            model=model,
            temperature=0.7
        )
        
        return response['choices'][0]['message']['content']
    
    async def summarize_document(
        self,
        content: str,
        max_length: int = 200
    ) -> str:
        """Summarize a document using LiteLLM"""
        
        messages = [
            {
                "role": "system",
                "content": f"Summarize the following document in {max_length} words or less:"
            },
            {
                "role": "user",
                "content": content
            }
        ]
        
        response = await self.client.chat_completion(
            messages=messages,
            model="claude-3-sonnet",  # Good for summarization
            temperature=0.3
        )
        
        return response['choices'][0]['message']['content']
```

### 3.3 Update Search Runner
```python
# onyx/context/search/retrieval/search_runner.py
from onyx.llm.litellm_client import LiteLLMClient
from onyx.vector_store.pgvector_client import PgVectorClient

class SearchRunner:
    def __init__(self):
        self.llm_client = LiteLLMClient()
        self.vector_client = PgVectorClient(
            host=os.getenv('VECTOR_DB_HOST'),
            port=int(os.getenv('VECTOR_DB_PORT')),
            database=os.getenv('VECTOR_DB_NAME'),
            user=os.getenv('POSTGRES_USER'),
            password=os.getenv('POSTGRES_PASSWORD')
        )
    
    async def search_and_answer(
        self,
        query: str,
        user_tier: str = "basic"
    ) -> Dict[str, Any]:
        """Search for relevant documents and generate answer"""
        
        # Generate query embedding
        query_embedding = await self.llm_client.generate_embeddings(query)
        
        # Search for similar documents
        similar_docs = self.vector_client.search_similar(
            query_embedding=query_embedding,
            limit=5,
            threshold=0.7
        )
        
        if not similar_docs:
            return {
                "answer": "I couldn't find relevant information to answer your question.",
                "sources": [],
                "confidence": 0.0
            }
        
        # Generate answer using LLM
        answer = await self.llm_client.answer_question(
            question=query,
            context=similar_docs,
            user_tier=user_tier
        )
        
        return {
            "answer": answer,
            "sources": similar_docs,
            "confidence": max([doc.get('similarity', 0) for doc in similar_docs])
        }
```

## 🧪 Testing the Integration

### 3.1 Test LiteLLM Proxy
```bash
# Test LiteLLM proxy health
curl http://litellm-proxy.onyx-infra.svc.cluster.local:4000/health

# Test model list
curl -H "Authorization: Bearer litellm-master-key" \
     http://litellm-proxy.onyx-infra.svc.cluster.local:4000/v1/models

# Test chat completion
curl -X POST \
     -H "Authorization: Bearer litellm-master-key" \
     -H "Content-Type: application/json" \
     -d '{
       "model": "gpt-3.5-turbo",
       "messages": [{"role": "user", "content": "Hello!"}]
     }' \
     http://litellm-proxy.onyx-infra.svc.cluster.local:4000/chat/completions
```

### 3.2 Test Onyx Integration
```python
# test_litellm_integration.py
import asyncio
from onyx.llm.llm_provider import LLMProvider

async def test_integration():
    provider = LLMProvider()
    
    # Test question answering
    answer = await provider.answer_question(
        question="What is Onyx?",
        context=[{"title": "Onyx Docs", "content": "Onyx is a knowledge management platform."}],
        user_tier="basic"
    )
    
    print(f"Answer: {answer}")
    
    # Test document summarization
    summary = await provider.summarize_document(
        content="This is a long document about various topics...",
        max_length=100
    )
    
    print(f"Summary: {summary}")

if __name__ == "__main__":
    asyncio.run(test_integration())
```

## 📊 Benefits of Integration

### 1. **Unified LLM Interface**
- Single endpoint for all LLM operations
- Easy switching between providers
- Consistent API across models

### 2. **Cost Optimization**
- Route queries to appropriate models
- Automatic fallback to cheaper models
- Response caching to reduce API calls

### 3. **Improved Reliability**
- Automatic failover between providers
- Load balancing across API keys
- Rate limiting to prevent quota exhaustion

### 4. **Better Monitoring**
- Centralized logging of LLM usage
- Cost tracking per user/team
- Performance metrics

## 🚀 Next Steps

1. **Deploy LiteLLM**: Follow `LITELLM-DEPLOYMENT-GUIDE.md`
2. **Migrate to pgvector**: Use `VESPA-TO-PGVECTOR-MIGRATION.md`
3. **Test Integration**: Run integration tests
4. **Monitor Performance**: Track metrics and costs
5. **Optimize Configuration**: Tune routing rules

## 📚 Additional Resources

- [LiteLLM Documentation](https://docs.litellm.ai/)
- [OpenAI API Compatibility](https://docs.litellm.ai/docs/providers/openai_compatible_server)
- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [Onyx LLM Integration](https://docs.onyx.ai/llm-integration/)
