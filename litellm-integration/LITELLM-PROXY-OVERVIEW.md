# LiteLLM Proxy Overview

## 🤔 What is LiteLLM Proxy?

LiteLLM proxy is a unified API gateway that allows you to use multiple Large Language Model (LLM) providers through a single, consistent interface. Think of it as a "universal translator" for AI models.

## 🎯 Why Use LiteLLM Proxy with Onyx?

### 1. **Provider Flexibility**
- Switch between OpenAI, Anthropic, Google, Azure, local models, etc.
- No code changes in Onyx when switching providers
- A/B test different models easily

### 2. **Cost Optimization**
```yaml
# Route different tasks to different models
routing_rules:
  - task: "simple_qa"
    model: "gpt-3.5-turbo"  # Cheaper for simple tasks
  - task: "complex_analysis" 
    model: "gpt-4"           # More capable for complex tasks
```

### 3. **Fallback & Reliability**
```yaml
# Automatic failover
models:
  - model_name: "gpt-4"
    litellm_params:
      model: "gpt-4"
      fallbacks: ["gpt-3.5-turbo", "claude-3-sonnet"]
```

### 4. **Rate Limiting & Caching**
- Prevent API quota exhaustion
- Cache responses to reduce costs
- Built-in request throttling

### 5. **Unified Interface**
```python
# Same code works with any provider
response = openai.ChatCompletion.create(
    model="gpt-4",  # Could be any model
    messages=[{"role": "user", "content": "Hello"}]
)
```

## 🏗️ How LiteLLM Works

### Basic Flow
```
Onyx Request → LiteLLM Proxy → LLM Provider → Response → Onyx
```

### Advanced Flow with Features
```
Onyx Request → LiteLLM Proxy → [Routing Logic] → [Caching] → [Rate Limiting] → LLM Provider
                                                                    ↓
Onyx Response ← [Response Processing] ← [Fallback Logic] ← Response
```

## 🔧 Key Features

### 1. **Model Routing**
```yaml
# Route based on request characteristics
routing:
  - condition: "user_tier == 'premium'"
    model: "gpt-4"
  - condition: "user_tier == 'basic'"
    model: "gpt-3.5-turbo"
```

### 2. **Response Caching**
```yaml
# Cache responses to reduce costs
caching:
  enabled: true
  ttl: 3600  # 1 hour
  key_generation: "user_id + prompt_hash"
```

### 3. **Cost Tracking**
```yaml
# Track usage per user/team
budget_limits:
  - user_id: "user123"
    monthly_limit: 100.00
    currency: "USD"
```

### 4. **Load Balancing**
```yaml
# Distribute load across multiple API keys
load_balancing:
  - provider: "openai"
    api_keys: ["key1", "key2", "key3"]
    strategy: "round_robin"
```

## 🆚 LiteLLM vs Direct API Calls

| Feature | Direct API | LiteLLM Proxy |
|---------|------------|---------------|
| **Provider Lock-in** | ❌ Hard to switch | ✅ Easy switching |
| **Fallback Support** | ❌ Manual coding | ✅ Built-in |
| **Cost Optimization** | ❌ Manual routing | ✅ Automatic |
| **Rate Limiting** | ❌ Per-provider limits | ✅ Unified limits |
| **Caching** | ❌ Manual implementation | ✅ Built-in |
| **Monitoring** | ❌ Scattered logs | ✅ Centralized |
| **A/B Testing** | ❌ Complex setup | ✅ Simple routing |

## 🎯 Use Cases for Onyx

### 1. **Multi-Provider Strategy**
```yaml
# Use different models for different Onyx features
models:
  - feature: "search_qa"
    model: "gpt-3.5-turbo"  # Fast, cheap for search
  - feature: "document_analysis"
    model: "gpt-4"          # More capable for analysis
  - feature: "summarization"
    model: "claude-3-sonnet" # Good at summarization
```

### 2. **Cost Control**
```yaml
# Set budgets per Onyx user/team
budget_limits:
  - team: "engineering"
    daily_limit: 50.00
  - team: "marketing"
    daily_limit: 200.00
```

### 3. **Reliability**
```yaml
# Ensure Onyx always works
fallbacks:
  - primary: "openai"
    fallback: "anthropic"
    fallback: "azure"
```

## 🔄 Integration with Onyx Architecture

### Current Onyx Flow
```
User Query → Onyx UI → Onyx API → Vector Search → LLM → Response
```

### With LiteLLM Proxy
```
User Query → Onyx UI → Onyx API → Vector Search → LiteLLM Proxy → LLM → Response
```

### Benefits for Onyx
1. **Unified LLM Interface**: Onyx API talks to one endpoint
2. **Provider Flexibility**: Switch models without code changes
3. **Cost Optimization**: Route queries to appropriate models
4. **Reliability**: Automatic failover ensures uptime
5. **Monitoring**: Centralized LLM usage tracking

## 🚀 Next Steps

1. **Read Integration Guide**: `ONYX-LITELLM-INTEGRATION.md`
2. **Plan Migration**: `VESPA-TO-PGVECTOR-MIGRATION.md`
3. **Deploy LiteLLM**: `LITELLM-DEPLOYMENT-GUIDE.md`
4. **Configure Examples**: `CONFIGURATION-EXAMPLES.md`

## 📚 Additional Resources

- [LiteLLM Documentation](https://docs.litellm.ai/)
- [OpenAI API Compatibility](https://docs.litellm.ai/docs/providers/openai_compatible_server)
- [pgvector Documentation](https://github.com/pgvector/pgvector)
- [Onyx Documentation](https://docs.onyx.ai/)
