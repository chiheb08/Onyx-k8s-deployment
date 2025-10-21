# LiteLLM Proxy Integration with Onyx

This folder contains documentation and configurations for integrating LiteLLM proxy as a backend for Onyx, including migration from Vespa to pgvector.

## 📁 Contents

- **[LITELLM-PROXY-OVERVIEW.md](LITELLM-PROXY-OVERVIEW.md)** - What is LiteLLM proxy and why use it
- **[ONYX-LITELLM-INTEGRATION.md](ONYX-LITELLM-INTEGRATION.md)** - How to integrate LiteLLM with Onyx
- **[VESPA-TO-PGVECTOR-MIGRATION.md](VESPA-TO-PGVECTOR-MIGRATION.md)** - Complete migration guide from Vespa to pgvector
- **[LITELLM-DEPLOYMENT-GUIDE.md](LITELLM-DEPLOYMENT-GUIDE.md)** - Kubernetes deployment for LiteLLM proxy
- **[CONFIGURATION-EXAMPLES.md](CONFIGURATION-EXAMPLES.md)** - Real configuration examples
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** - Common issues and solutions

## 🚀 Quick Start

1. **Read the Overview**: Start with `LITELLM-PROXY-OVERVIEW.md`
2. **Plan Migration**: Review `VESPA-TO-PGVECTOR-MIGRATION.md`
3. **Deploy LiteLLM**: Follow `LITELLM-DEPLOYMENT-GUIDE.md`
4. **Configure Onyx**: Use `ONYX-LITELLM-INTEGRATION.md`
5. **Test & Troubleshoot**: Reference `TROUBLESHOOTING.md`

## 🎯 Key Benefits

- **Unified LLM Interface**: Single endpoint for multiple LLM providers
- **Cost Optimization**: Route to cheapest models per use case
- **Fallback Support**: Automatic failover between providers
- **Rate Limiting**: Built-in request throttling
- **Caching**: Reduce costs with response caching
- **pgvector Integration**: Native PostgreSQL vector operations

## 📊 Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Onyx UI       │    │  LiteLLM Proxy   │    │  LLM Providers  │
│                 │───▶│                  │───▶│                 │
│  (Next.js)      │    │  (Unified API)   │    │  OpenAI, etc.   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │
         │                        │
         ▼                        ▼
┌─────────────────┐    ┌──────────────────┐
│   Onyx API      │    │   PostgreSQL     │
│                 │    │   + pgvector    │
│  (FastAPI)      │    │   (Vector DB)   │
└─────────────────┘    └──────────────────┘
```

## 🔧 Prerequisites

- Kubernetes/OpenShift cluster
- PostgreSQL with pgvector extension
- LiteLLM proxy deployment
- Onyx minimal deployment running

## 📝 Migration Checklist

- [ ] Review current Vespa setup
- [ ] Plan pgvector schema
- [ ] Deploy LiteLLM proxy
- [ ] Update Onyx configuration
- [ ] Test vector operations
- [ ] Migrate existing data
- [ ] Update monitoring
- [ ] Performance testing
