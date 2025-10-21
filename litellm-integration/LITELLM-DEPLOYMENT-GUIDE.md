# LiteLLM Proxy Deployment Guide

## 🎯 Overview

This guide provides step-by-step instructions for deploying LiteLLM proxy in your Kubernetes/OpenShift cluster to work with Onyx.

## 📋 Prerequisites

- Kubernetes/OpenShift cluster
- kubectl/oc CLI configured
- Access to LLM provider API keys (OpenAI, Anthropic, etc.)
- Redis instance (for caching)

## 🚀 Step 1: Create LiteLLM Configuration

### 1.1 Create LiteLLM ConfigMap
```yaml
# litellm-integration/manifests/litellm-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: litellm-config
  namespace: onyx-infra
data:
  config.yaml: |
    # Model configuration
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
      - model_name: gpt-4-turbo
        litellm_params:
          model: gpt-4-turbo-preview
          api_key: ${OPENAI_API_KEY}
      
      # Anthropic Models
      - model_name: claude-3-sonnet
        litellm_params:
          model: claude-3-sonnet-20240229
          api_key: ${ANTHROPIC_API_KEY}
      - model_name: claude-3-haiku
        litellm_params:
          model: claude-3-haiku-20240307
          api_key: ${ANTHROPIC_API_KEY}
      
      # Google Models
      - model_name: gemini-pro
        litellm_params:
          model: gemini-pro
          api_key: ${GOOGLE_API_KEY}
      
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
      - condition: "task_type == 'simple_qa'"
        model: "gpt-3.5-turbo"
      - condition: "task_type == 'complex_analysis'"
        model: "gpt-4"
    
    # Caching configuration
    cache:
      type: "redis"
      host: "redis.onyx-infra.svc.cluster.local"
      port: 6379
      password: "${REDIS_PASSWORD}"
      ttl: 3600  # 1 hour
      key_generation: "user_id + model + prompt_hash"
    
    # Rate limiting
    rate_limits:
      - model: "gpt-4"
        rpm: 60  # requests per minute
        tpm: 150000  # tokens per minute
      - model: "gpt-3.5-turbo"
        rpm: 300
        tpm: 300000
      - model: "claude-3-sonnet"
        rpm: 100
        tpm: 200000
    
    # Fallback configuration
    fallbacks:
      - model: "gpt-4"
        fallback: "gpt-3.5-turbo"
        fallback: "claude-3-sonnet"
      - model: "gpt-3.5-turbo"
        fallback: "claude-3-haiku"
      - model: "claude-3-sonnet"
        fallback: "gpt-3.5-turbo"
    
    # Load balancing
    load_balancing:
      - provider: "openai"
        api_keys: ["${OPENAI_API_KEY_1}", "${OPENAI_API_KEY_2}"]
        strategy: "round_robin"
    
    # Budget limits
    budget_limits:
      - user_id: "onyx-admin"
        monthly_limit: 1000.00
        currency: "USD"
      - user_id: "onyx-user"
        monthly_limit: 100.00
        currency: "USD"
```

### 1.2 Create LiteLLM Secret
```yaml
# litellm-integration/manifests/litellm-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: litellm-secret
  namespace: onyx-infra
type: Opaque
data:
  # Base64 encoded values
  master-key: bGl0ZWxsbS1tYXN0ZXIta2V5  # litellm-master-key
  openai-api-key: <base64-encoded-openai-key>
  anthropic-api-key: <base64-encoded-anthropic-key>
  google-api-key: <base64-encoded-google-key>
  redis-password: <base64-encoded-redis-password>
```

## 🚀 Step 2: Deploy LiteLLM Proxy

### 2.1 Create LiteLLM Deployment
```yaml
# litellm-integration/manifests/litellm-proxy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: litellm-proxy
  namespace: onyx-infra
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
            - name: OPENAI_API_KEY
              valueFrom:
                secretKeyRef:
                  name: litellm-secret
                  key: openai-api-key
            - name: ANTHROPIC_API_KEY
              valueFrom:
                secretKeyRef:
                  name: litellm-secret
                  key: anthropic-api-key
            - name: GOOGLE_API_KEY
              valueFrom:
                secretKeyRef:
                  name: litellm-secret
                  key: google-api-key
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: litellm-secret
                  key: redis-password
          command:
            - litellm
            - --config
            - /app/config.yaml
            - --port
            - "4000"
            - --host
            - "0.0.0.0"
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
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /health
              port: 4000
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
      volumes:
        - name: litellm-config
          configMap:
            name: litellm-config
---
apiVersion: v1
kind: Service
metadata:
  name: litellm-proxy
  namespace: onyx-infra
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

### 2.2 Create LiteLLM ServiceMonitor (for Prometheus)
```yaml
# litellm-integration/manifests/litellm-monitoring.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: litellm-proxy
  namespace: onyx-infra
  labels:
    app: litellm-proxy
spec:
  selector:
    matchLabels:
      app: litellm-proxy
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

## 🚀 Step 3: Deploy LiteLLM

### 3.1 Apply Manifests
```bash
# Apply LiteLLM configuration
kubectl apply -f litellm-integration/manifests/litellm-config.yaml
kubectl apply -f litellm-integration/manifests/litellm-secret.yaml
kubectl apply -f litellm-integration/manifests/litellm-proxy.yaml
kubectl apply -f litellm-integration/manifests/litellm-monitoring.yaml
```

### 3.2 Verify Deployment
```bash
# Check deployment status
kubectl get pods -n onyx-infra -l app=litellm-proxy

# Check service
kubectl get svc -n onyx-infra litellm-proxy

# Check logs
kubectl logs -n onyx-infra -l app=litellm-proxy --tail=50
```

## 🧪 Step 4: Test LiteLLM Proxy

### 4.1 Test Health Endpoint
```bash
# Test health endpoint
curl http://litellm-proxy.onyx-infra.svc.cluster.local:4000/health

# Expected response:
# {"status": "healthy"}
```

### 4.2 Test Model List
```bash
# Get available models
curl -H "Authorization: Bearer litellm-master-key" \
     http://litellm-proxy.onyx-infra.svc.cluster.local:4000/v1/models

# Expected response:
# {
#   "object": "list",
#   "data": [
#     {"id": "gpt-4", "object": "model", "created": 1677610602},
#     {"id": "gpt-3.5-turbo", "object": "model", "created": 1677610602}
#   ]
# }
```

### 4.3 Test Chat Completion
```bash
# Test chat completion
curl -X POST \
     -H "Authorization: Bearer litellm-master-key" \
     -H "Content-Type: application/json" \
     -d '{
       "model": "gpt-3.5-turbo",
       "messages": [
         {"role": "user", "content": "Hello! How are you?"}
       ],
       "temperature": 0.7,
       "max_tokens": 100
     }' \
     http://litellm-proxy.onyx-infra.svc.cluster.local:4000/chat/completions

# Expected response:
# {
#   "id": "chatcmpl-123",
#   "object": "chat.completion",
#   "created": 1677652288,
#   "model": "gpt-3.5-turbo",
#   "choices": [
#     {
#       "index": 0,
#       "message": {
#         "role": "assistant",
#         "content": "Hello! I'm doing well, thank you for asking. How can I help you today?"
#       },
#       "finish_reason": "stop"
#     }
#   ],
#   "usage": {
#     "prompt_tokens": 12,
#     "completion_tokens": 20,
#     "total_tokens": 32
#   }
# }
```

### 4.4 Test Embeddings
```bash
# Test embeddings
curl -X POST \
     -H "Authorization: Bearer litellm-master-key" \
     -H "Content-Type: application/json" \
     -d '{
       "model": "text-embedding-ada-002",
       "input": "Hello world"
     }' \
     http://litellm-proxy.onyx-infra.svc.cluster.local:4000/embeddings

# Expected response:
# {
#   "object": "list",
#   "data": [
#     {
#       "object": "embedding",
#       "index": 0,
#       "embedding": [0.0023064255, -0.009327292, ...]
#     }
#   ],
#   "model": "text-embedding-ada-002",
#   "usage": {
#     "prompt_tokens": 2,
#     "total_tokens": 2
#   }
# }
```

## 🔧 Step 5: Configure Onyx Integration

### 5.1 Update Onyx ConfigMap
```yaml
# Add to manifests/05-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: onyx-config
data:
  # ... existing configuration ...
  
  # LiteLLM proxy configuration
  LITELLM_PROXY_URL: "http://litellm-proxy.onyx-infra.svc.cluster.local:4000"
  LITELLM_PROXY_API_KEY: "litellm-master-key"
  
  # LLM configuration
  LLM_MODEL: "gpt-4"
  LLM_TEMPERATURE: "0.7"
  LLM_MAX_TOKENS: "4000"
```

### 5.2 Update API Server Deployment
```yaml
# Add to manifests/07-api-server.yaml
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
```

## 📊 Step 6: Monitoring and Observability

### 6.1 Create LiteLLM Dashboard
```yaml
# litellm-integration/manifests/litellm-dashboard.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: litellm-dashboard
  namespace: onyx-infra
data:
  dashboard.json: |
    {
      "dashboard": {
        "title": "LiteLLM Proxy Dashboard",
        "panels": [
          {
            "title": "Request Rate",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(litellm_requests_total[5m])",
                "legendFormat": "Requests/sec"
              }
            ]
          },
          {
            "title": "Token Usage",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(litellm_tokens_total[5m])",
                "legendFormat": "Tokens/sec"
              }
            ]
          },
          {
            "title": "Error Rate",
            "type": "graph",
            "targets": [
              {
                "expr": "rate(litellm_errors_total[5m])",
                "legendFormat": "Errors/sec"
              }
            ]
          }
        ]
      }
    }
```

### 6.2 Create LiteLLM Alerts
```yaml
# litellm-integration/manifests/litellm-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: litellm-alerts
  namespace: onyx-infra
spec:
  groups:
    - name: litellm.rules
      rules:
        - alert: LiteLLMHighErrorRate
          expr: rate(litellm_errors_total[5m]) > 0.1
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "LiteLLM proxy has high error rate"
            description: "LiteLLM proxy error rate is {{ $value }} errors/sec"
        
        - alert: LiteLLMHighLatency
          expr: histogram_quantile(0.95, rate(litellm_request_duration_seconds_bucket[5m])) > 10
          for: 2m
          labels:
            severity: warning
          annotations:
            summary: "LiteLLM proxy has high latency"
            description: "LiteLLM proxy 95th percentile latency is {{ $value }}s"
```

## 🚀 Step 7: Deploy and Test

### 7.1 Deploy All Components
```bash
# Deploy LiteLLM
kubectl apply -f litellm-integration/manifests/

# Deploy Onyx with LiteLLM integration
kubectl apply -f manifests/

# Check all pods
kubectl get pods -n onyx-infra
```

### 7.2 Test End-to-End
```bash
# Test Onyx API with LiteLLM
curl -X POST \
     -H "Content-Type: application/json" \
     -d '{
       "query": "What is Onyx?",
       "user_tier": "basic"
     }' \
     http://api-server.onyx-infra.svc.cluster.local:8080/query

# Test with premium user
curl -X POST \
     -H "Content-Type: application/json" \
     -d '{
       "query": "Explain the architecture of Onyx",
       "user_tier": "premium"
     }' \
     http://api-server.onyx-infra.svc.cluster.local:8080/query
```

## 🔧 Troubleshooting

### Common Issues

#### 1. LiteLLM Proxy Not Starting
```bash
# Check logs
kubectl logs -n onyx-infra -l app=litellm-proxy

# Check configuration
kubectl describe configmap litellm-config -n onyx-infra
```

#### 2. API Key Issues
```bash
# Check secret
kubectl get secret litellm-secret -n onyx-infra -o yaml

# Test API key
curl -H "Authorization: Bearer your-api-key" \
     http://litellm-proxy.onyx-infra.svc.cluster.local:4000/v1/models
```

#### 3. Redis Connection Issues
```bash
# Check Redis connectivity
kubectl exec -it deploy/litellm-proxy -n onyx-infra -- \
  redis-cli -h redis.onyx-infra.svc.cluster.local -p 6379 ping
```

## 📚 Additional Resources

- [LiteLLM Documentation](https://docs.litellm.ai/)
- [OpenAI API Compatibility](https://docs.litellm.ai/docs/providers/openai_compatible_server)
- [Redis Configuration](https://docs.litellm.ai/docs/providers/redis)
- [Monitoring Setup](https://docs.litellm.ai/docs/observability/monitoring)
