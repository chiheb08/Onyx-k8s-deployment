# Storage and Retrieval in On-Prem RAG (Onyx Example)

This document clarifies:
- MinIO vs NetApp in on-prem environments
- Why object storage and vector DB both exist in RAG
- Exact retrieval path in Onyx
- Tokenizer/chunking/file upload behavior
- Real bottlenecks in on-prem RAG and how to mitigate them

The goal is practical production guidance, not theory.

---

## 1) Storage layers in Onyx (what each one does)

Onyx is multi-storage by design. This is intentional and correct for production.

### 1.1 PostgreSQL (control plane and metadata)
- users, auth, groups, roles
- connector definitions and state
- indexing job metadata, attempts, status
- settings for embedding/rerank/retrieval behavior

This is your source of truth for system state and permissions metadata.

### 1.2 Object storage (MinIO/S3/NetApp S3) for raw files
- original uploaded files (PDF, DOCX, etc.)
- large binary payloads
- durable file store independent of API pod lifecycle

This is cheap and scalable for bytes, not for semantic search.

### 1.3 Vector/search database (Vespa, optionally OpenSearch paths)
- embeddings (vectors)
- chunk text and searchable fields
- retrieval indexes and ranking structures
- access-control-aware retrieval

This is optimized for low-latency retrieval and ranking, not for binary object durability.

---

## 2) MinIO vs NetApp (on-prem trade-offs)

## 2.1 MinIO strengths
- simple S3-compatible endpoint for app integration
- fast to deploy inside Kubernetes
- flexible and cost-effective
- strong throughput when correctly backed by fast storage/network

## 2.2 MinIO risks
- operations overhead is on your team (upgrades, policies, lifecycle)
- misconfiguration of credentials/policies is common
- small-object heavy workloads can expose backend storage inefficiencies
- bucket bootstrap is often forgotten in fresh environments

## 2.3 NetApp strengths (S3 offerings / ONTAP-backed environments)
- enterprise data management features
- mature snapshots/replication/protection tooling
- better fit if your org already runs NetApp and wants integrated ops

## 2.4 NetApp risks
- higher platform complexity/cost
- product family selection matters (not every mode fits tiny object-heavy workloads equally)
- still requires correct S3 policy modeling for app principals

## 2.5 Decision guideline
- If you need fast platform autonomy and Kubernetes-native operation: MinIO is often faster to ship.
- If you need enterprise storage governance and existing NetApp operational maturity: NetApp S3 options can reduce organizational friction.
- In both cases, RAG success depends more on indexing/retrieval pipeline tuning than object store brand alone.

---

## 3) Why object storage + vector DB both exist (even if embeddings are “stored in S3”)

This confusion is common, so be explicit:

- Object storage stores files as objects (blobs).
- Vector DB stores vectorized chunks + search indexes.

If you only keep embeddings in object storage:
- retrieval becomes slow (you must load/scan large datasets externally)
- you lose ANN/hybrid ranking efficiencies
- query latency and tail latency explode under load

RAG systems separate:
- **durability plane** (object store)
- **retrieval plane** (vector/search engine)
- **control plane** (relational metadata)

That separation is what gives predictable performance and recovery behavior.

---

## 4) Retrieval flow in Onyx (end-to-end)

## 4.1 Ingestion and indexing flow
1. file arrives (upload/connector), raw bytes stored in object storage
2. parser extracts text/structure
3. text split into chunks
4. chunks embedded by selected embedding model
5. vectors + chunk metadata written to Vespa (and optional additional index paths)
6. job state/attempt metadata persisted in Postgres

## 4.2 Query-time retrieval flow
1. user query enters API
2. query embedding is computed with current active embedding config
3. retrieval engine searches indexed chunks (semantic + optional keyword/hybrid logic)
4. ACL/permission filters are applied to candidate chunks
5. optional reranker reorders results
6. selected chunks become context for generation model
7. LLM generates answer with citations

Important operational note:
- If indexing is incomplete or swap not promoted, you can get “file uploaded but not found in answers.”
- This is a state-sync problem between indexing pipeline and active search settings.

---

## 5) Tokenizer, chunking, and why they matter in production

## 5.1 Tokenizer role
- controls model-side length accounting
- drives chunk boundary and truncation behavior
- influences embedding quality and retrieval recall

Tokenizer mismatch or bad truncation assumptions causes silent quality loss.

## 5.2 Chunking reality
- too large: topical dilution, higher embed cost, slower retrieval/rerank
- too small: loss of context, poor answer grounding
- bad boundaries: critical facts split across chunks and never co-retrieved

In production, chunking errors look like:
- “answer missed obvious fact in document”
- inconsistent results across similar queries
- low trust in citations

## 5.3 Practical defaults for stability-first deployments
- disable expensive advanced indexing until baseline is stable:
  - multipass indexing = false
  - contextual rag = false (initially)
- tune chunking with real query logs, not only offline assumptions

---

## 6) File upload path and failure points

## 6.1 Upload path
- client upload -> API validation -> object storage write -> enqueue processing -> parse/chunk/embed/index

## 6.2 Typical failures
- object store auth/policy mismatch (`AccessDenied`, `NoCredentials`)
- bucket missing at bootstrap
- parser timeout or malformed documents
- embedding provider latency/rate limit
- vector DB backpressure (`429 Too Many Requests` from Vespa feed)

## 6.3 Why uploads can appear “slow”
- not only network upload; most delay is post-upload processing:
  - parse + chunk + embed + index + retries
- if queue concurrency > storage/index capacity, latency spikes and retries amplify delay

---

## 7) Bottlenecks in on-prem RAG (and mitigation)

## 7.1 Object storage bottlenecks
Symptoms:
- upload success but indexing can’t fetch objects reliably
- intermittent AccessDenied/credential errors

Mitigations:
- enforce one credential source of truth
- standardize secret injection for API + all celery workers
- pre-create bucket in bootstrap (or idempotent job)
- verify endpoint, TLS mode, and addressing style consistency

## 7.2 Embedding bottlenecks
Symptoms:
- queue growth, long indexing times, frequent timeouts

Mitigations:
- reduce concurrent indexing workers until stable
- align thread counts with CPU cores and provider limits
- avoid model switches during peak indexing periods

## 7.3 Vector DB bottlenecks (Vespa backpressure)
Symptoms:
- HTTP 429 on feed
- “indexed status” lagging or repeated retries

Mitigations:
- reduce producer rate:
  - docprocessing concurrency
  - indexing workers
  - batch size
  - prefetch multiplier
- scale Vespa resources and storage IOPS
- temporarily disable extra indexing paths during large reindex windows

## 7.4 Queue and state bottlenecks
Symptoms:
- uploaded files never become retrievable
- stuck in partial indexing states

Mitigations:
- monitor queue depth and per-stage latency
- alert on aging tasks and swap-not-promoted states
- use explicit runbooks for model switch and rollback

---

## 8) Observability that should be mandatory on-prem

- object storage: auth failures, request latency, 4xx/5xx rates
- indexing workers: task duration, retries, queue depth
- Vespa feed/query latency and 429 counts
- retrieval quality checks:
  - recall on known-answer test set
  - citation correctness spot checks
- token/embedding cost and throughput per model

Without this, teams debug symptoms instead of root causes.

---

## 9) Recommended architecture posture for your Onyx deployment

1. Keep multi-layer storage model (Postgres + object store + vector DB).
2. For MinIO:
   - automate bucket creation
   - standardize credential wiring and pod restarts on secret change
3. Keep indexing conservative until stable, then scale gradually.
4. Use API-driven embedding switch runbook when UI path is unreliable.
5. Stabilize retrieval before enabling expensive features (multipass/contextual).
6. Treat 429 as capacity signal, not transient noise.

---

## 10) Quick answers to your core questions

- **MinIO vs NetApp?**  
  MinIO is simpler/faster to operate in K8s; NetApp can be stronger for enterprise data governance if your org already has that platform maturity.

- **Why object storage + vector DB both?**  
  Object store is for durable files; vector DB is for low-latency semantic retrieval and ranking. They solve different problems.

- **If embeddings are in S3, why still vector DB?**  
  Because S3 is not a retrieval index engine. ANN/hybrid ranking at scale requires purpose-built indexes.

- **How retrieval is done?**  
  Query embed -> vector/hybrid search over indexed chunks -> ACL filter -> optional rerank -> LLM generation with cited context.

- **Main on-prem bottlenecks?**  
  Credentials/policy drift, parser/embed latency, queue pressure, vector DB feed backpressure, and insufficient observability.

---

## References used for this research

- Onyx docs (security architecture, data flows/storage/system description)
- Onyx deployment values and platform configuration references
- Public technical analyses on MinIO + NetApp S3 operational characteristics
- Production RAG performance/chunking/retrieval latency guidance

Use this document as an operations architecture baseline and adapt thresholds to your workload profile.
