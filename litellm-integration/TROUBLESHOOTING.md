# LiteLLM Integration Troubleshooting Guide

## 🎯 Overview

This guide helps you troubleshoot common issues when integrating LiteLLM proxy with Onyx, including deployment problems, configuration issues, and performance optimization.

## 🔍 Common Issues and Solutions

### 1. LiteLLM Proxy Not Starting

#### Symptoms
- Pod stays in `Pending` or `CrashLoopBackOff` state
- Logs show configuration errors
- Health checks failing

#### Diagnosis
```bash
# Check pod status
kubectl get pods -n onyx-infra -l app=litellm-proxy

# Check pod logs
kubectl logs -n onyx-infra -l app=litellm-proxy --tail=50

# Check pod description
kubectl describe pod -n onyx-infra -l app=litellm-proxy
```

#### Solutions

##### 1.1 Configuration Issues
```bash
# Check ConfigMap
kubectl get configmap litellm-config -n onyx-infra -o yaml

# Verify YAML syntax
kubectl get configmap litellm-config -n onyx-infra -o jsonpath='{.data.config\.yaml}' | yq eval -P
```

**Fix**: Ensure YAML syntax is correct and all required fields are present.

##### 1.2 Secret Issues
```bash
# Check secret
kubectl get secret litellm-secret -n onyx-infra -o yaml

# Verify API keys are base64 encoded
echo "your-api-key" | base64
```

**Fix**: Ensure all API keys are properly base64 encoded in the secret.

##### 1.3 Resource Issues
```bash
# Check resource quotas
kubectl describe quota -n onyx-infra

# Check pod resource requests
kubectl describe pod -n onyx-infra -l app=litellm-proxy
```

**Fix**: Adjust resource requests/limits or increase namespace quotas.

### 2. API Key Authentication Failures

#### Symptoms
- 401 Unauthorized errors
- "Invalid API key" messages
- Authentication failures in logs

#### Diagnosis
```bash
# Test API key
curl -H "Authorization: Bearer your-api-key" \
     http://litellm-proxy.onyx-infra.svc.cluster.local:4000/v1/models

# Check secret content
kubectl get secret litellm-secret -n onyx-infra -o jsonpath='{.data.openai-api-key}' | base64 -d
```

#### Solutions

##### 2.1 Invalid API Key
```bash
# Verify API key format
echo "your-api-key" | wc -c  # Should be 51 characters for OpenAI

# Test with OpenAI directly
curl -H "Authorization: Bearer your-api-key" \
     https://api.openai.com/v1/models
```

**Fix**: Ensure API key is valid and has proper permissions.

##### 2.2 Base64 Encoding Issues
```bash
# Re-encode API key
echo "your-api-key" | base64

# Update secret
kubectl patch secret litellm-secret -n onyx-infra --type='json' \
  -p='[{"op": "replace", "path": "/data/openai-api-key", "value": "base64-encoded-key"}]'
```

**Fix**: Re-encode API key and update secret.

### 3. Model Routing Issues

#### Symptoms
- Wrong model being used
- Routing rules not working
- Fallback not triggering

#### Diagnosis
```bash
# Check routing configuration
kubectl get configmap litellm-config -n onyx-infra -o jsonpath='{.data.config\.yaml}' | yq eval '.routing'

# Test routing with different conditions
curl -X POST \
     -H "Authorization: Bearer litellm-master-key" \
     -H "Content-Type: application/json" \
     -d '{
       "model": "gpt-4",
       "messages": [{"role": "user", "content": "Hello"}],
       "user_tier": "premium"
     }' \
     http://litellm-proxy.onyx-infra.svc.cluster.local:4000/chat/completions
```

#### Solutions

##### 3.1 Routing Rule Syntax
```yaml
# Correct routing syntax
routing:
  - condition: "user_tier == 'premium'"
    model: "gpt-4"
  - condition: "user_tier == 'basic'"
    model: "gpt-3.5-turbo"
```

**Fix**: Ensure routing conditions use proper syntax and field names.

##### 3.2 Fallback Configuration
```yaml
# Correct fallback syntax
fallbacks:
  - model: "gpt-4"
    fallback: "gpt-3.5-turbo"
    fallback: "claude-3-sonnet"
```

**Fix**: Ensure fallback models are properly configured and available.

### 4. Redis Connection Issues

#### Symptoms
- Caching not working
- Redis connection errors
- Cache-related failures

#### Diagnosis
```bash
# Test Redis connectivity
kubectl exec -it deploy/litellm-proxy -n onyx-infra -- \
  redis-cli -h redis.onyx-infra.svc.cluster.local -p 6379 ping

# Check Redis logs
kubectl logs -n onyx-infra -l app=redis --tail=20
```

#### Solutions

##### 4.1 Redis Service Issues
```bash
# Check Redis service
kubectl get svc -n onyx-infra redis

# Check Redis endpoints
kubectl get endpoints -n onyx-infra redis
```

**Fix**: Ensure Redis service is running and accessible.

##### 4.2 Redis Authentication
```bash
# Test Redis with password
kubectl exec -it deploy/litellm-proxy -n onyx-infra -- \
  redis-cli -h redis.onyx-infra.svc.cluster.local -p 6379 -a your-password ping
```

**Fix**: Ensure Redis password is correct in LiteLLM configuration.

### 5. Performance Issues

#### Symptoms
- Slow response times
- High latency
- Timeout errors

#### Diagnosis
```bash
# Check pod resources
kubectl top pods -n onyx-infra -l app=litellm-proxy

# Check network connectivity
kubectl exec -it deploy/litellm-proxy -n onyx-infra -- \
  curl -w "@curl-format.txt" -o /dev/null -s http://api.openai.com/v1/models
```

#### Solutions

##### 5.1 Resource Constraints
```yaml
# Increase resource limits
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

**Fix**: Increase CPU and memory limits for LiteLLM proxy.

##### 5.2 Network Optimization
```yaml
# Optimize network settings
network:
  keep_alive: true
  timeout: 30s
  retries: 3
```

**Fix**: Optimize network configuration and connection pooling.

### 6. Onyx Integration Issues

#### Symptoms
- Onyx API can't connect to LiteLLM
- Authentication failures
- Model not found errors

#### Diagnosis
```bash
# Test LiteLLM from Onyx pod
kubectl exec -it deploy/api-server -n onyx-infra -- \
  curl -H "Authorization: Bearer litellm-master-key" \
       http://litellm-proxy.onyx-infra.svc.cluster.local:4000/v1/models

# Check Onyx configuration
kubectl get configmap onyx-config -n onyx-infra -o yaml
```

#### Solutions

##### 6.1 Configuration Mismatch
```yaml
# Ensure Onyx config matches LiteLLM
LITELLM_PROXY_URL: "http://litellm-proxy.onyx-infra.svc.cluster.local:4000"
LITELLM_PROXY_API_KEY: "litellm-master-key"
```

**Fix**: Ensure Onyx configuration matches LiteLLM proxy settings.

##### 6.2 Network Connectivity
```bash
# Test connectivity from Onyx pod
kubectl exec -it deploy/api-server -n onyx-infra -- \
  nslookup litellm-proxy.onyx-infra.svc.cluster.local
```

**Fix**: Ensure network policies allow communication between Onyx and LiteLLM.

## 🔧 Advanced Troubleshooting

### 1. Debug Mode

#### Enable Debug Logging
```yaml
# Add to LiteLLM configuration
logging:
  level: "DEBUG"
  format: "json"
  fields:
    - "request_id"
    - "user_id"
    - "model"
    - "tokens"
    - "cost"
    - "latency"
```

#### Check Debug Logs
```bash
# Get detailed logs
kubectl logs -n onyx-infra -l app=litellm-proxy --tail=100 -f
```

### 2. Performance Profiling

#### Enable Metrics
```yaml
# Add to LiteLLM configuration
monitoring:
  enabled: true
  metrics:
    - name: "litellm_requests_total"
      type: "counter"
    - name: "litellm_tokens_total"
      type: "counter"
    - name: "litellm_request_duration_seconds"
      type: "histogram"
```

#### Check Metrics
```bash
# Get metrics endpoint
curl http://litellm-proxy.onyx-infra.svc.cluster.local:4000/metrics
```

### 3. Load Testing

#### Test with Load
```bash
# Install hey (load testing tool)
go install github.com/rakyll/hey@latest

# Run load test
hey -n 100 -c 10 -H "Authorization: Bearer litellm-master-key" \
    -H "Content-Type: application/json" \
    -d '{"model": "gpt-3.5-turbo", "messages": [{"role": "user", "content": "Hello"}]}' \
    http://litellm-proxy.onyx-infra.svc.cluster.local:4000/chat/completions
```

## 📊 Monitoring and Alerting

### 1. Health Checks

#### Basic Health Check
```bash
# Check LiteLLM health
curl http://litellm-proxy.onyx-infra.svc.cluster.local:4000/health
```

#### Advanced Health Check
```bash
# Check with authentication
curl -H "Authorization: Bearer litellm-master-key" \
     http://litellm-proxy.onyx-infra.svc.cluster.local:4000/health
```

### 2. Metrics Collection

#### Prometheus Metrics
```yaml
# ServiceMonitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: litellm-proxy
  namespace: onyx-infra
spec:
  selector:
    matchLabels:
      app: litellm-proxy
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

#### Grafana Dashboard
```json
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
      }
    ]
  }
}
```

### 3. Alerting Rules

#### High Error Rate Alert
```yaml
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
```

## 🚀 Best Practices

### 1. Configuration Management

#### Use ConfigMaps for Configuration
```yaml
# Store configuration in ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: litellm-config
data:
  config.yaml: |
    # Your LiteLLM configuration
```

#### Use Secrets for Sensitive Data
```yaml
# Store API keys in secrets
apiVersion: v1
kind: Secret
metadata:
  name: litellm-secret
type: Opaque
data:
  openai-api-key: <base64-encoded>
  anthropic-api-key: <base64-encoded>
```

### 2. Resource Management

#### Set Appropriate Limits
```yaml
# Set resource limits
resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 2Gi
```

#### Use Horizontal Pod Autoscaling
```yaml
# Enable HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: litellm-proxy-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: litellm-proxy
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

### 3. Security

#### Use Network Policies
```yaml
# Restrict network access
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: litellm-proxy-policy
spec:
  podSelector:
    matchLabels:
      app: litellm-proxy
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-server
      ports:
        - protocol: TCP
          port: 4000
```

#### Use RBAC
```yaml
# Create service account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: litellm-proxy
  namespace: onyx-infra
---
# Create role binding
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: litellm-proxy
  namespace: onyx-infra
subjects:
  - kind: ServiceAccount
    name: litellm-proxy
    namespace: onyx-infra
roleRef:
  kind: Role
  name: litellm-proxy
  apiGroup: rbac.authorization.k8s.io
```

## 📚 Additional Resources

- [LiteLLM Documentation](https://docs.litellm.ai/)
- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug-application-cluster/)
- [OpenShift Troubleshooting](https://docs.openshift.com/container-platform/4.12/support/troubleshooting/)
- [Redis Troubleshooting](https://redis.io/docs/management/troubleshooting/)
