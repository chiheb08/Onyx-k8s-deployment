# LiteLLM Configuration Examples

## 🎯 Overview

This document provides real-world configuration examples for integrating LiteLLM proxy with Onyx, including routing rules, cost optimization, and monitoring setups.

## 🔧 Basic Configuration

### 1. Simple OpenAI Setup
```yaml
# Basic OpenAI configuration
model_list:
  - model_name: gpt-4
    litellm_params:
      model: gpt-4
      api_key: ${OPENAI_API_KEY}
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: gpt-3.5-turbo
      api_key: ${OPENAI_API_KEY}

# Basic routing
routing:
  - condition: "user_tier == 'premium'"
    model: "gpt-4"
  - condition: "user_tier == 'basic'"
    model: "gpt-3.5-turbo"
```

### 2. Multi-Provider Setup
```yaml
# Multiple providers with fallbacks
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
  - model_name: claude-3-haiku
    litellm_params:
      model: claude-3-haiku-20240307
      api_key: ${ANTHROPIC_API_KEY}
  
  # Google Models
  - model_name: gemini-pro
    litellm_params:
      model: gemini-pro
      api_key: ${GOOGLE_API_KEY}

# Fallback configuration
fallbacks:
  - model: "gpt-4"
    fallback: "gpt-3.5-turbo"
    fallback: "claude-3-sonnet"
  - model: "gpt-3.5-turbo"
    fallback: "claude-3-haiku"
  - model: "claude-3-sonnet"
    fallback: "gpt-3.5-turbo"
```

## 🎯 Advanced Routing Rules

### 1. Task-Based Routing
```yaml
# Route based on task type
routing:
  - condition: "task_type == 'summarization'"
    model: "claude-3-sonnet"  # Good for summarization
  - condition: "task_type == 'code_generation'"
    model: "gpt-4"  # Better for code
  - condition: "task_type == 'simple_qa'"
    model: "gpt-3.5-turbo"  # Cheaper for simple tasks
  - condition: "task_type == 'complex_analysis'"
    model: "gpt-4"  # More capable for complex tasks
  - condition: "task_type == 'creative_writing'"
    model: "claude-3-sonnet"  # Good for creative tasks
```

### 2. User Tier Routing
```yaml
# Route based on user tier
routing:
  - condition: "user_tier == 'premium'"
    model: "gpt-4"
  - condition: "user_tier == 'basic'"
    model: "gpt-3.5-turbo"
  - condition: "user_tier == 'enterprise'"
    model: "gpt-4-turbo"
```

### 3. Time-Based Routing
```yaml
# Route based on time of day
routing:
  - condition: "hour >= 9 && hour <= 17"
    model: "gpt-4"  # Use premium model during business hours
  - condition: "hour < 9 || hour > 17"
    model: "gpt-3.5-turbo"  # Use cheaper model outside business hours
```

### 4. Content Length Routing
```yaml
# Route based on input length
routing:
  - condition: "input_length > 4000"
    model: "gpt-4"  # Use more capable model for long inputs
  - condition: "input_length <= 4000"
    model: "gpt-3.5-turbo"  # Use cheaper model for short inputs
```

## 💰 Cost Optimization

### 1. Budget Limits
```yaml
# Set monthly budgets per user/team
budget_limits:
  - user_id: "onyx-admin"
    monthly_limit: 1000.00
    currency: "USD"
  - user_id: "onyx-user"
    monthly_limit: 100.00
    currency: "USD"
  - team: "engineering"
    daily_limit: 200.00
    currency: "USD"
  - team: "marketing"
    daily_limit: 500.00
    currency: "USD"
```

### 2. Cost-Based Routing
```yaml
# Route to cheapest model when possible
routing:
  - condition: "task_complexity == 'low'"
    model: "gpt-3.5-turbo"  # Cheapest option
  - condition: "task_complexity == 'medium'"
    model: "claude-3-haiku"  # Good balance of cost/performance
  - condition: "task_complexity == 'high'"
    model: "gpt-4"  # Most capable but expensive
```

### 3. Response Caching
```yaml
# Cache responses to reduce costs
cache:
  type: "redis"
  host: "redis.onyx-infra.svc.cluster.local"
  port: 6379
  password: "${REDIS_PASSWORD}"
  ttl: 3600  # 1 hour
  key_generation: "user_id + model + prompt_hash"
  
# Cache configuration per model
cache_config:
  - model: "gpt-3.5-turbo"
    ttl: 7200  # 2 hours for cheaper model
  - model: "gpt-4"
    ttl: 1800  # 30 minutes for expensive model
```

## 🔄 Load Balancing

### 1. Round Robin
```yaml
# Distribute load across multiple API keys
load_balancing:
  - provider: "openai"
    api_keys: ["${OPENAI_API_KEY_1}", "${OPENAI_API_KEY_2}", "${OPENAI_API_KEY_3}"]
    strategy: "round_robin"
```

### 2. Weighted Round Robin
```yaml
# Weighted distribution
load_balancing:
  - provider: "openai"
    api_keys: 
      - key: "${OPENAI_API_KEY_1}"
        weight: 3
      - key: "${OPENAI_API_KEY_2}"
        weight: 2
      - key: "${OPENAI_API_KEY_3}"
        weight: 1
    strategy: "weighted_round_robin"
```

### 3. Least Connections
```yaml
# Route to least busy endpoint
load_balancing:
  - provider: "openai"
    api_keys: ["${OPENAI_API_KEY_1}", "${OPENAI_API_KEY_2}"]
    strategy: "least_connections"
```

## 🚦 Rate Limiting

### 1. Per-Model Rate Limits
```yaml
# Set rate limits per model
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
```

### 2. Per-User Rate Limits
```yaml
# Set rate limits per user
rate_limits:
  - user_id: "onyx-admin"
    rpm: 100
    tpm: 200000
  - user_id: "onyx-user"
    rpm: 50
    tpm: 100000
```

### 3. Global Rate Limits
```yaml
# Set global rate limits
rate_limits:
  - global:
      rpm: 1000
      tpm: 1000000
```

## 📊 Monitoring and Observability

### 1. Prometheus Metrics
```yaml
# Enable Prometheus metrics
monitoring:
  enabled: true
  metrics:
    - name: "litellm_requests_total"
      type: "counter"
      help: "Total number of requests"
    - name: "litellm_tokens_total"
      type: "counter"
      help: "Total number of tokens"
    - name: "litellm_errors_total"
      type: "counter"
      help: "Total number of errors"
    - name: "litellm_request_duration_seconds"
      type: "histogram"
      help: "Request duration in seconds"
```

### 2. Logging Configuration
```yaml
# Configure logging
logging:
  level: "INFO"
  format: "json"
  fields:
    - "request_id"
    - "user_id"
    - "model"
    - "tokens"
    - "cost"
```

### 3. Alerting Rules
```yaml
# Alert on high error rates
alerts:
  - name: "HighErrorRate"
    condition: "rate(litellm_errors_total[5m]) > 0.1"
    severity: "warning"
    message: "LiteLLM proxy has high error rate"
  
  - name: "HighLatency"
    condition: "histogram_quantile(0.95, rate(litellm_request_duration_seconds_bucket[5m])) > 10"
    severity: "warning"
    message: "LiteLLM proxy has high latency"
```

## 🔐 Security Configuration

### 1. API Key Management
```yaml
# Secure API key handling
security:
  api_keys:
    - name: "onyx-admin"
      key: "${ONYX_ADMIN_KEY}"
      permissions: ["read", "write", "admin"]
    - name: "onyx-user"
      key: "${ONYX_USER_KEY}"
      permissions: ["read", "write"]
  
  # Rate limiting per API key
  rate_limits:
    - api_key: "onyx-admin"
      rpm: 100
      tpm: 200000
    - api_key: "onyx-user"
      rpm: 50
      tpm: 100000
```

### 2. IP Whitelisting
```yaml
# Restrict access by IP
security:
  ip_whitelist:
    - "10.0.0.0/8"  # Internal network
    - "192.168.0.0/16"  # Private network
```

### 3. Request Validation
```yaml
# Validate requests
security:
  validation:
    max_tokens: 4000
    max_messages: 50
    allowed_models: ["gpt-4", "gpt-3.5-turbo", "claude-3-sonnet"]
```

## 🧪 Testing Configuration

### 1. Test Environment
```yaml
# Test configuration
test_config:
  models:
    - model_name: "gpt-3.5-turbo"
      litellm_params:
        model: "gpt-3.5-turbo"
        api_key: "${OPENAI_API_KEY}"
  
  # Test routing
  routing:
    - condition: "test_mode == true"
      model: "gpt-3.5-turbo"
  
  # Test rate limits
  rate_limits:
    - model: "gpt-3.5-turbo"
      rpm: 10  # Lower limits for testing
      tpm: 10000
```

### 2. Load Testing
```yaml
# Load testing configuration
load_test:
  concurrent_users: 10
  requests_per_user: 100
  test_duration: "5m"
  models: ["gpt-3.5-turbo", "gpt-4"]
```

## 📚 Production Configuration

### 1. High Availability
```yaml
# High availability configuration
ha:
  replicas: 3
  health_check:
    interval: 30s
    timeout: 10s
    retries: 3
  
  # Circuit breaker
  circuit_breaker:
    failure_threshold: 5
    recovery_timeout: 60s
```

### 2. Performance Tuning
```yaml
# Performance configuration
performance:
  # Connection pooling
  connection_pool:
    max_connections: 100
    max_idle_connections: 10
    connection_timeout: 30s
  
  # Request timeout
  request_timeout: 60s
  
  # Response compression
  compression:
    enabled: true
    level: 6
```

### 3. Backup and Recovery
```yaml
# Backup configuration
backup:
  # Redis backup
  redis:
    enabled: true
    schedule: "0 2 * * *"  # Daily at 2 AM
    retention: "7d"
  
  # Configuration backup
  config:
    enabled: true
    schedule: "0 1 * * *"  # Daily at 1 AM
    retention: "30d"
```

## 🚀 Deployment Examples

### 1. Development Environment
```yaml
# Development configuration
development:
  models:
    - model_name: "gpt-3.5-turbo"
      litellm_params:
        model: "gpt-3.5-turbo"
        api_key: "${OPENAI_API_KEY}"
  
  # Lower rate limits for development
  rate_limits:
    - model: "gpt-3.5-turbo"
      rpm: 10
      tpm: 10000
  
  # No caching in development
  cache:
    enabled: false
```

### 2. Staging Environment
```yaml
# Staging configuration
staging:
  models:
    - model_name: "gpt-3.5-turbo"
      litellm_params:
        model: "gpt-3.5-turbo"
        api_key: "${OPENAI_API_KEY}"
    - model_name: "gpt-4"
      litellm_params:
        model: "gpt-4"
        api_key: "${OPENAI_API_KEY}"
  
  # Moderate rate limits
  rate_limits:
    - model: "gpt-3.5-turbo"
      rpm: 50
      tpm: 50000
    - model: "gpt-4"
      rpm: 20
      tpm: 20000
  
  # Enable caching
  cache:
    enabled: true
    ttl: 1800  # 30 minutes
```

### 3. Production Environment
```yaml
# Production configuration
production:
  models:
    - model_name: "gpt-3.5-turbo"
      litellm_params:
        model: "gpt-3.5-turbo"
        api_key: "${OPENAI_API_KEY}"
    - model_name: "gpt-4"
      litellm_params:
        model: "gpt-4"
        api_key: "${OPENAI_API_KEY}"
    - model_name: "claude-3-sonnet"
      litellm_params:
        model: "claude-3-sonnet-20240229"
        api_key: "${ANTHROPIC_API_KEY}"
  
  # High rate limits
  rate_limits:
    - model: "gpt-3.5-turbo"
      rpm: 300
      tpm: 300000
    - model: "gpt-4"
      rpm: 60
      tpm: 150000
  
  # Full caching
  cache:
    enabled: true
    ttl: 3600  # 1 hour
    key_generation: "user_id + model + prompt_hash"
  
  # Full monitoring
  monitoring:
    enabled: true
    metrics: true
    logging: true
    alerting: true
```

## 📚 Additional Resources

- [LiteLLM Configuration Reference](https://docs.litellm.ai/docs/providers/)
- [OpenAI API Documentation](https://platform.openai.com/docs/api-reference)
- [Anthropic API Documentation](https://docs.anthropic.com/)
- [Google AI API Documentation](https://ai.google.dev/docs)
