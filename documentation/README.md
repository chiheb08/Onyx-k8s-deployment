# Documentation

Technical documentation and architecture guides for Onyx Kubernetes deployment.

---

## 📚 Architecture Guides

### [ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md](ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md)
Complete architecture explanation designed for junior engineers and those new to Onyx. Includes:
- Complete system overview
- Component explanations
- Data flow diagrams
- Integration patterns

**Read this first** to understand the overall system!

### [KUBERNETES-NETWORKING-COMPLETE-GUIDE.md](KUBERNETES-NETWORKING-COMPLETE-GUIDE.md)
Comprehensive networking guide covering:
- Kubernetes networking fundamentals
- Services (ClusterIP, NodePort, LoadBalancer)
- OpenShift Routes
- Network Policies
- Company-only access setup
- Security best practices

**Essential for** understanding how components communicate!

---

## 🤖 Model Servers

### [MODEL-SERVERS-EXPLANATION.md](MODEL-SERVERS-EXPLANATION.md)
Deep dive into Inference and Indexing model servers:
- What they do and why we need them
- Differences between inference and indexing
- How they work together
- Resource requirements

### [MODEL-SERVERS-YAML-EXPLAINED.md](MODEL-SERVERS-YAML-EXPLAINED.md)
Line-by-line explanation of model server YAML manifests:
- Environment variables
- Volume mounts
- Resource specifications
- Health checks

### [HUGGING-FACE-MODELS-FLOW.md](HUGGING-FACE-MODELS-FLOW.md)
How HuggingFace models are downloaded and cached:
- Model download process
- Cache directory structure
- Offline/airgapped deployment
- Volume management

### [AIRGAPPED-MODEL-SERVERS-GUIDE.md](AIRGAPPED-MODEL-SERVERS-GUIDE.md)
Complete guide for deploying model servers in airgapped environments:
- Pre-downloading models
- Creating custom images
- Manual model loading
- Volume setup

---

## 🔄 User Flow

### [END-TO-END-USER-FLOW.md](END-TO-END-USER-FLOW.md)
Complete user request flow from browser to response:
- User query processing
- Embedding generation
- Vector search
- LLM integration
- Response delivery

**Read this** to understand how a user request flows through the system!

---

## 📖 Reading Order

For newcomers, we recommend reading in this order:

1. **[ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md](ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md)**
   - Get the big picture first

2. **[KUBERNETES-NETWORKING-COMPLETE-GUIDE.md](KUBERNETES-NETWORKING-COMPLETE-GUIDE.md)**
   - Understand how components connect

3. **[END-TO-END-USER-FLOW.md](END-TO-END-USER-FLOW.md)**
   - See how user requests are processed

4. **[MODEL-SERVERS-EXPLANATION.md](MODEL-SERVERS-EXPLANATION.md)**
   - Deep dive into AI/ML components

5. **Model Server Specific Docs** (as needed)
   - YAML explanations
   - HuggingFace models
   - Airgapped deployment

---

## 🎯 Quick Reference

### For Understanding Architecture
→ [ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md](ARCHITECTURE-FOR-JUNIOR-ENGINEERS.md)

### For Networking Issues
→ [KUBERNETES-NETWORKING-COMPLETE-GUIDE.md](KUBERNETES-NETWORKING-COMPLETE-GUIDE.md)

### For Model Server Issues
→ [MODEL-SERVERS-EXPLANATION.md](MODEL-SERVERS-EXPLANATION.md)
→ [HUGGING-FACE-MODELS-FLOW.md](HUGGING-FACE-MODELS-FLOW.md)

### For Airgapped Deployment
→ [AIRGAPPED-MODEL-SERVERS-GUIDE.md](AIRGAPPED-MODEL-SERVERS-GUIDE.md)

### For Understanding User Flows
→ [END-TO-END-USER-FLOW.md](END-TO-END-USER-FLOW.md)
