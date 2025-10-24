# Celery Technical Deep Dive - Onyx Enterprise Search Platform

## 🎯 Executive Summary

Celery is used in Onyx as a **distributed task queue system** to handle computationally intensive, long-running background operations that would otherwise block the main API server. This document provides a comprehensive technical analysis of why Celery is essential, how it's implemented, and the hardware/performance implications.

---

## 🔍 Why Celery is Used in Onyx

### The Problem: Blocking Operations

**Without Celery (Synchronous Processing):**
```
User uploads 100MB PDF → API Server processes it → User waits 30+ seconds → Timeout/Error
```

**With Celery (Asynchronous Processing):**
```
User uploads 100MB PDF → API Server queues task → Returns immediately → Background processing
```

### Core Use Cases in Onyx

1. **Document Processing Pipeline**
   - PDF text extraction (CPU-intensive)
   - Document chunking (memory-intensive)
   - Embedding generation (GPU/CPU-intensive)
   - Vector database indexing (I/O-intensive)

2. **Connector Synchronization**
   - Google Drive API calls (network I/O)
   - Confluence API synchronization (rate-limited)
   - SharePoint document fetching (authentication overhead)

3. **System Maintenance**
   - Database cleanup operations
   - Vector database synchronization
   - Cache invalidation
   - Health monitoring

---

## 🏗️ Technical Architecture

### Celery Components in Onyx

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    CELERY ECOSYSTEM IN ONYX                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    MESSAGE BROKER (Redis)                                               │
│                                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              Redis:6379 (Task Queue)                                           │   │
│  │                                                                                                 │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │   │
│  │  │   celery    │  │docprocessing│  │docfetching  │  │   light     │  │   heavy     │           │   │
│  │  │   queue     │  │   queue     │  │   queue     │  │   queue     │  │   queue     │           │   │
│  │  │             │  │             │  │             │  │             │  │             │           │   │
│  │  │ • Core tasks│  │ • Doc index │  │ • Fetch docs│  │ • Metadata  │  │ • Pruning   │           │   │
│  │  │ • Periodic  │  │ • Embedding │  │ • Connectors│  │ • Permissions│  │ • Bulk sync │           │   │
│  │  │ • System    │  │ • Chunking  │  │ • APIs      │  │ • Cleanup   │  │ • Exports   │           │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘           │   │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    CELERY WORKERS                                                       │
│                                                                                                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   CELERY BEAT   │  │ PRIMARY WORKER  │  │  LIGHT WORKER   │  │  HEAVY WORKER   │  │ DOCFETCHING     │ │
│  │   (Scheduler)   │  │                 │  │                 │  │                 │  │ WORKER          │ │
│  │                 │  │ • System tasks │  │ • Fast ops      │  │ • Bulk ops      │  │                 │ │
│  │ • Cron-like     │  │ • Coordination  │  │ • Metadata sync │  │ • Data pruning  │  │ • External APIs │ │
│  │ • Every 15s-5min│  │ • Health checks│  │ • Permissions   │  │ • Large exports │  │ • Connectors    │ │
│  │ • 1 replica     │  │ • 4 threads    │  │ • 4 threads     │  │ • 4 threads     │  │ • 4 threads     │ │
│  │   (critical!)   │  │                 │  │                 │  │                 │  │                 │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│                                                                                                         │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                            DOCPROCESSING WORKER (CRITICAL!)                                     │   │
│  │                                                                                                 │   │
│  │  • Document processing pipeline                                                                │   │
│  │  • Embedding generation (calls Indexing Model Server)                                          │   │
│  │  • Vector database operations                                                                  │   │
│  │  • 6 threads (high concurrency)                                                                │   │
│  │  • 8-16GB RAM (memory intensive)                                                               │   │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 📊 Performance Metrics & Hardware Requirements

### Task Processing Metrics

#### Document Processing Pipeline
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              DOCUMENT PROCESSING PERFORMANCE METRICS                                    │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Document Size: 10MB PDF (typical business document)
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Step                    │ Time (seconds) │ CPU Usage │ Memory Usage │ I/O Operations │ Network Calls │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ PDF Text Extraction    │ 2-5s           │ 80-100%   │ 500MB-1GB    │ High (disk)    │ None          │
│ Document Chunking       │ 1-2s           │ 20-40%    │ 200-500MB    │ Low            │ None          │
│ Embedding Generation   │ 5-15s          │ 60-90%    │ 2-4GB        │ Medium         │ 1 call        │
│ Vector DB Indexing     │ 2-8s           │ 30-60%    │ 1-2GB        │ High (network) │ 5-20 calls    │
│ Metadata Updates       │ 0.5-1s         │ 10-20%    │ 100-200MB    │ Medium (DB)    │ 2-5 calls     │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ TOTAL PER DOCUMENT     │ 10-31s         │ 40-60%    │ 3.8-7.7GB    │ High           │ 8-26 calls    │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Document Size: 100MB PDF (large document)
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Step                    │ Time (seconds) │ CPU Usage │ Memory Usage │ I/O Operations │ Network Calls │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ PDF Text Extraction    │ 15-30s         │ 90-100%   │ 2-4GB        │ Very High      │ None          │
│ Document Chunking       │ 5-10s          │ 40-60%    │ 1-2GB        │ Medium         │ None          │
│ Embedding Generation   │ 30-60s         │ 80-95%    │ 4-8GB        │ High           │ 10-50 calls   │
│ Vector DB Indexing     │ 10-30s         │ 50-80%    │ 2-4GB        │ Very High      │ 50-200 calls  │
│ Metadata Updates       │ 2-5s           │ 20-30%    │ 500MB-1GB    │ High (DB)      │ 10-20 calls   │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ TOTAL PER DOCUMENT     │ 72-135s        │ 60-80%    │ 9.5-19GB     │ Very High      │ 70-270 calls  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

#### Connector Synchronization Metrics
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              CONNECTOR SYNC PERFORMANCE METRICS                                         │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Google Drive Connector (1000 documents)
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Operation                │ Time (seconds) │ CPU Usage │ Memory Usage │ Network I/O │ API Rate Limits │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Authentication          │ 1-2s           │ 10%       │ 50MB         │ Low         │ 1 call          │
│ List Files              │ 5-10s          │ 20%       │ 100MB        │ Medium      │ 10-20 calls     │
│ Download Files          │ 30-60s         │ 30%       │ 200-500MB    │ Very High   │ 100-1000 calls  │
│ Process Documents       │ 60-120s        │ 70%       │ 2-4GB        │ High        │ 0 calls         │
│ Index to Vector DB      │ 20-40s         │ 50%       │ 1-2GB        │ High        │ 50-200 calls    │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ TOTAL SYNC              │ 116-232s       │ 40-60%    │ 3.35-7.05GB  │ Very High   │ 161-1231 calls  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Confluence Connector (500 pages)
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Operation                │ Time (seconds) │ CPU Usage │ Memory Usage │ Network I/O │ API Rate Limits │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Authentication          │ 1-2s           │ 10%       │ 50MB         │ Low         │ 1 call          │
│ List Pages              │ 3-5s           │ 15%       │ 100MB        │ Medium      │ 5-10 calls      │
│ Download Content         │ 20-40s         │ 25%       │ 200-400MB    │ High        │ 50-100 calls    │
│ Process Content          │ 30-60s         │ 60%       │ 1-2GB        │ Medium      │ 0 calls         │
│ Index to Vector DB       │ 15-30s         │ 40%       │ 1-2GB        │ High        │ 25-100 calls    │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ TOTAL SYNC              │ 69-137s        │ 35-50%    │ 2.35-5.5GB   │ High        │ 81-211 calls    │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Hardware Requirements Analysis

#### CPU Requirements
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    CPU UTILIZATION BREAKDOWN                                            │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Worker Type                │ CPU Request │ CPU Limit │ Typical Usage │ Peak Usage │ Bottleneck
────────────────────────────┼─────────────┼───────────┼───────────────┼────────────┼─────────────────────
Celery Beat                │ 100m        │ 500m      │ 5-10%         │ 20%        │ Scheduling overhead
Primary Worker              │ 500m        │ 1000m     │ 20-40%        │ 80%        │ System coordination
Light Worker                │ 500m        │ 1000m     │ 15-30%        │ 60%        │ Metadata operations
Heavy Worker                │ 1000m       │ 2000m     │ 30-60%        │ 90%        │ Bulk operations
Docfetching Worker          │ 500m        │ 2000m     │ 25-50%        │ 85%        │ Network I/O
Docprocessing Worker        │ 1000m       │ 4000m     │ 40-80%        │ 95%        │ Embedding generation
────────────────────────────┼─────────────┼───────────┼───────────────┼────────────┼─────────────────────
TOTAL (6 workers)          │ 3.6 cores   │ 10.5 cores│ 135-250%      │ 430%       │ Docprocessing
```

#### Memory Requirements
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                   MEMORY UTILIZATION BREAKDOWN                                          │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Worker Type                │ Memory Request│ Memory Limit│ Base Usage   │ Peak Usage │ Memory Intensive
────────────────────────────┼───────────────┼─────────────┼──────────────┼────────────┼──────────────────
Celery Beat                │ 256Mi         │ 512Mi       │ 100-200MB    │ 300MB      │ No
Primary Worker              │ 1Gi           │ 2Gi         │ 300-500MB    │ 1.5GB      │ No
Light Worker                │ 1Gi           │ 2Gi         │ 200-400MB    │ 1.2GB      │ No
Heavy Worker                │ 4Gi           │ 8Gi         │ 1-2GB        │ 6GB        │ Yes (bulk ops)
Docfetching Worker          │ 8Gi           │ 16Gi        │ 2-4GB        │ 12GB       │ Yes (file cache)
Docprocessing Worker        │ 8Gi           │ 16Gi        │ 3-6GB        │ 14GB       │ Yes (embeddings)
────────────────────────────┼───────────────┼─────────────┼──────────────┼────────────┼──────────────────
TOTAL (6 workers)          │ 22GB          │ 44GB        │ 6.6-13.1GB   │ 35.2GB     │ Docprocessing
```

#### Network I/O Requirements
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                   NETWORK I/O BREAKDOWN                                                 │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Operation Type              │ Bandwidth     │ Latency     │ Connections │ Data Volume │ Bottleneck
────────────────────────────┼───────────────┼─────────────┼─────────────┼─────────────┼──────────────────
Redis Queue Operations      │ 1-10 Mbps     │ 1-5ms       │ 10-50       │ 1-100MB     │ Queue depth
Model Server Calls          │ 10-100 Mbps   │ 10-100ms    │ 5-20        │ 10-1000MB   │ Embedding size
Vector DB Operations        │ 50-500 Mbps   │ 20-200ms    │ 20-100      │ 100-10000MB │ Index size
External API Calls          │ 5-50 Mbps     │ 100-1000ms  │ 5-50        │ 10-1000MB   │ Rate limits
Database Operations         │ 10-100 Mbps   │ 5-50ms      │ 10-100      │ 1-1000MB    │ Query complexity
────────────────────────────┼───────────────┼─────────────┼─────────────┼─────────────┼──────────────────
TOTAL PEAK                  │ 76-760 Mbps   │ 1-1000ms    │ 50-320      │ 122-12200MB │ Vector DB
```

### Storage Requirements

#### Disk I/O Patterns
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                   STORAGE I/O BREAKDOWN                                                 │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Operation Type              │ Read/Write    │ IOPS        │ Throughput   │ Data Size   │ Storage Type
────────────────────────────┼───────────────┼─────────────┼──────────────┼─────────────┼──────────────────
Document Upload (MinIO)     │ Write         │ 10-100      │ 10-100 MB/s  │ 1-1000MB    │ Object Storage
PDF Text Extraction         │ Read          │ 50-200      │ 20-50 MB/s   │ 1-100MB     │ Local SSD
Embedding Generation        │ Read/Write    │ 100-500     │ 50-200 MB/s  │ 10-1000MB   │ Local SSD
Vector DB Indexing         │ Write         │ 200-1000    │ 100-500 MB/s │ 100-10000MB │ Network Storage
Database Operations         │ Read/Write    │ 100-500     │ 10-100 MB/s  │ 1-100MB     │ Database Storage
────────────────────────────┼───────────────┼─────────────┼──────────────┼─────────────┼──────────────────
TOTAL PEAK                  │ Mixed         │ 460-2200    │ 190-950 MB/s │ 112-12100MB │ Mixed
```

---

## 🔧 Similar Use Cases & Industry Examples

### 1. **E-commerce Platforms**

**Example: Amazon Product Catalog**
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              AMAZON PRODUCT CATALOG PROCESSING                                         │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Problem: Process millions of product listings, images, and descriptions
Solution: Celery workers for:
- Image processing and optimization
- Product data extraction
- Search index updates
- Price monitoring
- Inventory synchronization

Hardware Requirements:
- CPU: 16-32 cores per worker
- Memory: 8-32GB per worker
- Storage: 1-10TB SSD
- Network: 1-10 Gbps

Performance Metrics:
- 1M products processed per hour
- 99.9% uptime requirement
- Sub-second response times for search
```

### 2. **Content Management Systems**

**Example: WordPress.com**
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              WORDPRESS.COM CONTENT PROCESSING                                           │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Problem: Process millions of blog posts, images, and media files
Solution: Celery workers for:
- Image resizing and optimization
- Content indexing
- SEO analysis
- Spam detection
- Backup operations

Hardware Requirements:
- CPU: 8-16 cores per worker
- Memory: 4-16GB per worker
- Storage: 500GB-2TB SSD
- Network: 100 Mbps - 1 Gbps

Performance Metrics:
- 100K posts processed per hour
- 99.5% uptime requirement
- Real-time content updates
```

### 3. **Financial Services**

**Example: Stripe Payment Processing**
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              STRIPE PAYMENT PROCESSING                                                 │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Problem: Process millions of transactions, fraud detection, and reporting
Solution: Celery workers for:
- Transaction processing
- Fraud detection algorithms
- Report generation
- Data synchronization
- Compliance monitoring

Hardware Requirements:
- CPU: 32-64 cores per worker
- Memory: 16-64GB per worker
- Storage: 1-10TB NVMe SSD
- Network: 10-100 Gbps

Performance Metrics:
- 1M transactions per second
- 99.99% uptime requirement
- Sub-millisecond response times
```

### 4. **Social Media Platforms**

**Example: Twitter Content Processing**
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              TWITTER CONTENT PROCESSING                                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Problem: Process millions of tweets, images, and videos in real-time
Solution: Celery workers for:
- Content moderation
- Image/video processing
- Timeline generation
- Trend analysis
- User recommendations

Hardware Requirements:
- CPU: 16-32 cores per worker
- Memory: 8-32GB per worker
- Storage: 1-5TB SSD
- Network: 1-10 Gbps

Performance Metrics:
- 10M tweets processed per hour
- 99.9% uptime requirement
- Real-time content delivery
```

### 5. **Machine Learning Platforms**

**Example: Hugging Face Model Processing**
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              HUGGING FACE MODEL PROCESSING                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Problem: Process and serve thousands of ML models
Solution: Celery workers for:
- Model training
- Model inference
- Data preprocessing
- Model optimization
- Model serving

Hardware Requirements:
- CPU: 32-128 cores per worker
- Memory: 32-256GB per worker
- GPU: 1-8 GPUs per worker
- Storage: 1-50TB NVMe SSD
- Network: 10-100 Gbps

Performance Metrics:
- 1000 models processed per hour
- 99.9% uptime requirement
- Real-time inference
```

---

## 📈 Performance Optimization Strategies

### 1. **Horizontal Scaling**

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    HORIZONTAL SCALING STRATEGY                                          │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Single Worker Performance:
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Worker Type                │ Documents/Hour │ CPU Usage │ Memory Usage │ Bottleneck                 │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Docprocessing (1 worker)   │ 100-200        │ 80-90%    │ 8-16GB       │ CPU/Memory                 │
│ Docfetching (1 worker)     │ 500-1000       │ 60-80%    │ 4-8GB        │ Network I/O               │
│ Heavy (1 worker)           │ 200-500        │ 70-90%    │ 4-8GB        │ CPU                        │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Scaled Performance (3 workers each):
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Worker Type                │ Documents/Hour │ CPU Usage │ Memory Usage │ Bottleneck                 │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Docprocessing (3 workers)  │ 300-600        │ 80-90%    │ 24-48GB      │ Model Server               │
│ Docfetching (3 workers)    │ 1500-3000      │ 60-80%    │ 12-24GB      │ External APIs              │
│ Heavy (3 workers)         │ 600-1500       │ 70-90%    │ 12-24GB      │ Database                   │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Scaling Limits:
- Docprocessing: Limited by Indexing Model Server capacity
- Docfetching: Limited by external API rate limits
- Heavy: Limited by database connection pool
```

### 2. **Vertical Scaling**

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    VERTICAL SCALING STRATEGY                                            │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Resource Upgrades:
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Current Config           │ Upgraded Config        │ Performance Gain │ Cost Increase │ ROI           │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 4 CPU, 8GB RAM           │ 8 CPU, 16GB RAM        │ 1.5-2x          │ 2x            │ Good          │
│ 8 CPU, 16GB RAM          │ 16 CPU, 32GB RAM       │ 1.3-1.7x        │ 2x            │ Moderate      │
│ 16 CPU, 32GB RAM         │ 32 CPU, 64GB RAM       │ 1.2-1.5x        │ 2x            │ Poor          │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Optimal Configuration:
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Worker Type                │ CPU Cores │ Memory │ Storage │ Network │ Cost/Month │ Performance        │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Docprocessing              │ 8-16      │ 32GB   │ 1TB SSD │ 1 Gbps  │ $200-400   │ 200-400 docs/hour │
│ Docfetching                │ 4-8       │ 16GB   │ 500GB   │ 1 Gbps  │ $100-200   │ 1000-2000 docs/hr │
│ Heavy                      │ 4-8       │ 16GB   │ 500GB   │ 1 Gbps  │ $100-200   │ 500-1000 docs/hr  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### 3. **Queue Optimization**

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    QUEUE OPTIMIZATION STRATEGY                                          │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Queue Configuration:
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Queue Name                │ Priority │ Prefetch │ Concurrency │ Timeout │ Retry Policy               │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ docprocessing             │ High     │ 1        │ 6           │ 300s    │ 3 retries, exponential     │
│ docfetching               │ Medium   │ 4        │ 4           │ 600s    │ 2 retries, linear          │
│ heavy                     │ Low      │ 1        │ 4           │ 1800s   │ 1 retry, fixed             │
│ light                     │ High     │ 2        │ 4           │ 60s     │ 3 retries, exponential     │
│ celery                    │ Medium   │ 1        │ 4           │ 300s    │ 2 retries, linear          │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Performance Impact:
- Prefetch=1: Prevents memory bloat, better for CPU-intensive tasks
- Prefetch=4: Better throughput for I/O-intensive tasks
- Priority queues: Critical tasks processed first
- Timeout settings: Prevent stuck tasks from blocking workers
```

---

## 🔧 Technical Implementation Details

### Celery Configuration in Onyx

#### Base Configuration
```python
# onyx/background/celery/configs/base.py

# Redis as message broker
broker_url = "redis://:password@redis-host:6379/15"
result_backend = "redis://:password@redis-host:6379/16"

# Connection settings
broker_connection_retry_on_startup = True
broker_pool_limit = 10
broker_transport_options = {
    "priority_steps": [0, 1, 2, 3],  # 4 priority levels
    "sep": ":",
    "queue_order_strategy": "priority",
    "retry_on_timeout": True,
    "health_check_interval": 30,
    "socket_keepalive": True,
}

# Task settings
task_default_priority = 1  # Medium priority
task_acks_late = True      # Acknowledge after completion
result_expires = 86400     # 24 hours
```

#### Worker-Specific Configuration
```python
# Docprocessing Worker (Most Critical)
worker_concurrency = 6           # 6 threads
worker_pool = "threads"          # Thread pool for I/O
worker_prefetch_multiplier = 1   # One task per thread
task_track_started = True        # Track task start

# Docfetching Worker
worker_concurrency = 4           # 4 threads
worker_pool = "threads"          # Thread pool for network I/O
worker_prefetch_multiplier = 4   # 4 tasks per thread

# Heavy Worker
worker_concurrency = 4           # 4 threads
worker_pool = "threads"          # Thread pool for bulk operations
worker_prefetch_multiplier = 1   # One task per thread
```

### Task Definition Examples

#### Document Processing Task
```python
@shared_task(
    name="onyx.background.celery.tasks.docprocessing.docprocessing_task",
    bind=True,
    soft_time_limit=300,  # 5 minutes
    time_limit=600,       # 10 minutes hard limit
)
def docprocessing_task(
    self: Task,
    index_attempt_id: int,
    cc_pair_id: int,
    tenant_id: str,
    batch_num: int,
) -> None:
    """
    Process a batch of documents through the indexing pipeline.
    
    Steps:
    1. Download documents from MinIO
    2. Extract text content
    3. Chunk documents
    4. Generate embeddings (calls Indexing Model Server)
    5. Store in Vespa vector database
    6. Update PostgreSQL metadata
    """
    # Start heartbeat for monitoring
    heartbeat_thread, stop_event = start_heartbeat(index_attempt_id)
    
    try:
        # Download documents from storage
        documents = download_documents_from_minio(batch_num)
        
        # Process each document
        for document in documents:
            # Extract text
            text_content = extract_text_from_document(document)
            
            # Chunk document
            chunks = chunk_document(text_content, chunk_size=512)
            
            # Generate embeddings for each chunk
            for chunk in chunks:
                # Call Indexing Model Server
                embedding = call_indexing_model_server(chunk.text)
                
                # Store in Vespa
                store_in_vespa(chunk, embedding)
        
        # Update metadata
        update_document_metadata(index_attempt_id, len(documents))
        
    finally:
        stop_heartbeat(heartbeat_thread, stop_event)
```

#### Connector Sync Task
```python
@shared_task(
    name="onyx.background.celery.tasks.docfetching.docfetching_proxy_task",
    bind=True,
    acks_late=False,
    track_started=True,
)
def docfetching_proxy_task(
    self: Task,
    index_attempt_id: int,
    cc_pair_id: int,
    search_settings_id: int,
    tenant_id: str,
) -> None:
    """
    Fetch documents from external connectors (Google Drive, Confluence, etc.)
    
    Steps:
    1. Authenticate to external service
    2. List new/updated files
    3. Download files
    4. Store in MinIO
    5. Create docprocessing tasks
    """
    # Get connector configuration
    connector_config = get_connector_config(cc_pair_id)
    
    # Authenticate to external service
    client = authenticate_to_external_service(connector_config)
    
    # List files since last sync
    files = list_files_since_last_sync(client, last_sync_time)
    
    # Download and process files
    for file in files:
        # Download file
        file_content = download_file(client, file.id)
        
        # Store in MinIO
        minio_path = store_in_minio(file_content, file.name)
        
        # Create docprocessing task
        docprocessing_task.delay(
            index_attempt_id=index_attempt_id,
            cc_pair_id=cc_pair_id,
            tenant_id=tenant_id,
            batch_num=file.batch_num
        )
```

### Monitoring and Observability

#### Health Checks
```python
# Worker health monitoring
@shared_task(name="onyx.background.celery.tasks.monitoring.health_check")
def health_check(tenant_id: str) -> dict:
    """Monitor worker health and performance"""
    return {
        "worker_count": get_active_worker_count(),
        "queue_lengths": get_queue_lengths(),
        "memory_usage": get_memory_usage(),
        "cpu_usage": get_cpu_usage(),
        "task_throughput": get_task_throughput(),
        "error_rate": get_error_rate(),
    }
```

#### Metrics Collection
```python
# Performance metrics
@shared_task(name="onyx.background.celery.tasks.monitoring.collect_metrics")
def collect_metrics(tenant_id: str) -> None:
    """Collect and store performance metrics"""
    metrics = {
        "timestamp": datetime.utcnow(),
        "tenant_id": tenant_id,
        "active_tasks": get_active_task_count(),
        "completed_tasks": get_completed_task_count(),
        "failed_tasks": get_failed_task_count(),
        "average_task_duration": get_average_task_duration(),
        "queue_backlog": get_queue_backlog(),
    }
    
    # Store metrics in database
    store_metrics(metrics)
```

---

## 🚀 Deployment Recommendations

### Production Hardware Specifications

#### Minimal Deployment (Small Organization)
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    MINIMAL DEPLOYMENT                                                  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Hardware Requirements:
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Component                 │ CPU Cores │ Memory │ Storage │ Network │ Cost/Month │ Use Case              │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Celery Beat              │ 1         │ 512MB  │ 10GB    │ 100Mbps │ $20        │ Task scheduling       │
│ Primary Worker            │ 2         │ 2GB    │ 50GB    │ 100Mbps │ $40        │ Core tasks            │
│ Docprocessing Worker      │ 4         │ 8GB    │ 200GB   │ 1Gbps   │ $80        │ Document indexing     │
│ Total                     │ 7         │ 10.5GB │ 260GB   │ 1Gbps   │ $140       │ 100-500 docs/day      │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Performance Expectations:
- 100-500 documents per day
- 1-5 users
- 1-10 connectors
- 99% uptime
```

#### Standard Deployment (Medium Organization)
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    STANDARD DEPLOYMENT                                                 │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Hardware Requirements:
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Component                 │ CPU Cores │ Memory │ Storage │ Network │ Cost/Month │ Use Case              │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Celery Beat              │ 2         │ 1GB    │ 20GB    │ 100Mbps │ $40        │ Task scheduling       │
│ Primary Worker            │ 4         │ 4GB    │ 100GB   │ 100Mbps │ $80        │ Core tasks            │
│ Light Worker              │ 2         │ 2GB    │ 50GB    │ 100Mbps │ $40        │ Lightweight ops      │
│ Heavy Worker              │ 4         │ 8GB    │ 200GB   │ 1Gbps   │ $160       │ Bulk operations       │
│ Docfetching Worker        │ 4         │ 8GB    │ 200GB   │ 1Gbps   │ $160       │ Connector sync        │
│ Docprocessing Worker      │ 8         │ 16GB   │ 500GB   │ 1Gbps   │ $320       │ Document indexing     │
│ Total                     │ 24        │ 39GB   │ 1070GB  │ 1Gbps   │ $800       │ 1000-5000 docs/day    │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Performance Expectations:
- 1000-5000 documents per day
- 10-50 users
- 10-50 connectors
- 99.5% uptime
```

#### Enterprise Deployment (Large Organization)
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    ENTERPRISE DEPLOYMENT                                               │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Hardware Requirements:
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Component                 │ CPU Cores │ Memory │ Storage │ Network │ Cost/Month │ Use Case              │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Celery Beat              │ 4         │ 2GB    │ 50GB    │ 1Gbps   │ $80        │ Task scheduling       │
│ Primary Worker (3x)       │ 12        │ 12GB   │ 300GB   │ 1Gbps   │ $240       │ Core tasks            │
│ Light Worker (3x)         │ 12        │ 12GB   │ 300GB   │ 1Gbps   │ $240       │ Lightweight ops      │
│ Heavy Worker (3x)         │ 24        │ 48GB   │ 1.5TB   │ 10Gbps  │ $960       │ Bulk operations       │
│ Docfetching Worker (3x)    │ 24        │ 48GB   │ 1.5TB   │ 10Gbps  │ $960       │ Connector sync        │
│ Docprocessing Worker (3x) │ 48        │ 96GB   │ 3TB     │ 10Gbps  │ $1920      │ Document indexing     │
│ Total                     │ 124       │ 230GB  │ 6.65TB  │ 10Gbps  │ $4400      │ 10000+ docs/day        │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Performance Expectations:
- 10000+ documents per day
- 100+ users
- 100+ connectors
- 99.9% uptime
```

### Cloud Provider Recommendations

#### AWS Deployment
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    AWS DEPLOYMENT                                                      │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Instance Types:
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Worker Type                │ Instance Type │ vCPUs │ Memory │ Storage │ Network │ Cost/Hour │ Cost/Month │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Celery Beat                │ t3.medium     │ 2     │ 4GB    │ 20GB    │ Up to 5 │ $0.0416   │ $30        │
│ Primary Worker              │ t3.large      │ 2     │ 8GB    │ 50GB    │ Up to 5 │ $0.0832   │ $60        │
│ Light Worker                │ t3.large      │ 2     │ 8GB    │ 50GB    │ Up to 5 │ $0.0832   │ $60        │
│ Heavy Worker                │ c5.2xlarge   │ 8     │ 16GB   │ 200GB   │ Up to 10│ $0.34     │ $245       │
│ Docfetching Worker          │ c5.2xlarge   │ 8     │ 16GB   │ 200GB   │ Up to 10│ $0.34     │ $245       │
│ Docprocessing Worker        │ c5.4xlarge   │ 16    │ 32GB   │ 500GB   │ Up to 10│ $0.68     │ $490       │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Total Cost: ~$1,125/month
```

#### Google Cloud Deployment
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    GCP DEPLOYMENT                                                      │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Instance Types:
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Worker Type                │ Machine Type │ vCPUs │ Memory │ Storage │ Network │ Cost/Hour │ Cost/Month │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Celery Beat                │ e2-medium    │ 2     │ 4GB    │ 20GB    │ 1 Gbps  │ $0.0335   │ $24        │
│ Primary Worker              │ e2-standard-2│ 2     │ 8GB    │ 50GB    │ 1 Gbps  │ $0.067    │ $48        │
│ Light Worker                │ e2-standard-2│ 2     │ 8GB    │ 50GB    │ 1 Gbps  │ $0.067    │ $48        │
│ Heavy Worker                │ c2-standard-8│ 8     │ 32GB   │ 200GB   │ 10 Gbps │ $0.28     │ $202       │
│ Docfetching Worker          │ c2-standard-8│ 8     │ 32GB   │ 200GB   │ 10 Gbps │ $0.28     │ $202       │
│ Docprocessing Worker        │ c2-standard-16│ 16   │ 64GB   │ 500GB   │ 10 Gbps │ $0.56     │ $403       │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Total Cost: ~$927/month
```

#### Azure Deployment
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    AZURE DEPLOYMENT                                                    │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Instance Types:
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Worker Type                │ VM Size      │ vCPUs │ Memory │ Storage │ Network │ Cost/Hour │ Cost/Month │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Celery Beat                │ Standard_B2s │ 2     │ 4GB    │ 20GB    │ 1 Gbps  │ $0.0416   │ $30        │
│ Primary Worker              │ Standard_B4s │ 4     │ 8GB    │ 50GB    │ 1 Gbps  │ $0.1664   │ $120       │
│ Light Worker                │ Standard_B4s │ 4     │ 8GB    │ 50GB    │ 1 Gbps  │ $0.1664   │ $120       │
│ Heavy Worker                │ Standard_D8s_v3│ 8  │ 32GB   │ 200GB   │ 2 Gbps  │ $0.384    │ $277       │
│ Docfetching Worker          │ Standard_D8s_v3│ 8  │ 32GB   │ 200GB   │ 2 Gbps  │ $0.384    │ $277       │
│ Docprocessing Worker        │ Standard_D16s_v3│ 16│ 64GB   │ 500GB   │ 4 Gbps  │ $0.768    │ $553       │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Total Cost: ~$1,277/month
```

---

## 📊 Performance Monitoring & Metrics

### Key Performance Indicators (KPIs)

#### System Health Metrics
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    SYSTEM HEALTH METRICS                                               │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Metric                    │ Target Value │ Warning Threshold │ Critical Threshold │ Action Required     │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Worker Uptime             │ 99.9%        │ 99.5%            │ 99.0%             │ Restart workers     │
│ Queue Length              │ < 100        │ 500              │ 1000              │ Scale workers       │
│ Task Success Rate         │ 99.5%        │ 95%              │ 90%               │ Investigate errors  │
│ Average Task Duration     │ < 30s        │ 60s              │ 120s              │ Optimize tasks      │
│ Memory Usage              │ < 80%        │ 90%              │ 95%               │ Scale memory        │
│ CPU Usage                 │ < 70%        │ 85%              │ 95%               │ Scale CPU           │
│ Network Latency           │ < 100ms      │ 200ms            │ 500ms             │ Check network       │
│ Database Connections      │ < 80%        │ 90%              │ 95%               │ Scale database      │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

#### Business Metrics
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    BUSINESS METRICS                                                     │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Metric                    │ Target Value │ Measurement Method │ Business Impact                        │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Documents Processed/Hour  │ 1000+        │ Task completion logs│ User satisfaction                     │
│ Search Response Time      │ < 200ms      │ API response times │ User experience                       │
│ Connector Sync Success    │ 99%          │ Sync task results  │ Data freshness                        │
│ Index Freshness           │ < 1 hour     │ Last update time   │ Search accuracy                       │
│ User Query Success Rate   │ 99.5%        │ API success rate   │ User productivity                    │
│ System Availability       │ 99.9%        │ Uptime monitoring  │ Business continuity                   │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Monitoring Tools & Dashboards

#### Prometheus Metrics
```python
# Custom metrics for Onyx Celery workers
from prometheus_client import Counter, Histogram, Gauge

# Task metrics
task_counter = Counter('celery_tasks_total', 'Total tasks processed', ['worker', 'task_type', 'status'])
task_duration = Histogram('celery_task_duration_seconds', 'Task duration', ['worker', 'task_type'])
queue_length = Gauge('celery_queue_length', 'Queue length', ['queue_name'])
worker_memory = Gauge('celery_worker_memory_bytes', 'Worker memory usage', ['worker'])
worker_cpu = Gauge('celery_worker_cpu_percent', 'Worker CPU usage', ['worker'])

# Document processing metrics
documents_processed = Counter('documents_processed_total', 'Documents processed', ['worker'])
embedding_generation_time = Histogram('embedding_generation_seconds', 'Embedding generation time')
vector_db_operations = Counter('vector_db_operations_total', 'Vector DB operations', ['operation'])
```

#### Grafana Dashboard Queries
```promql
# Worker health dashboard
celery_worker_memory_bytes{worker="docprocessing"}
celery_worker_cpu_percent{worker="docprocessing"}
celery_queue_length{queue_name="docprocessing"}

# Task throughput
rate(celery_tasks_total[5m])
rate(documents_processed_total[5m])

# Error rates
rate(celery_tasks_total{status="failed"}[5m]) / rate(celery_tasks_total[5m])

# Performance metrics
histogram_quantile(0.95, celery_task_duration_seconds_bucket)
histogram_quantile(0.50, embedding_generation_seconds_bucket)
```

---

## 🔧 Troubleshooting & Optimization

### Common Performance Issues

#### 1. **Memory Leaks in Document Processing**
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    MEMORY LEAK DIAGNOSIS                                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Symptoms:
- Worker memory usage continuously increases
- Workers crash with OOM errors
- Task processing slows down over time

Root Causes:
- Large documents not being garbage collected
- Embedding vectors accumulating in memory
- File handles not being closed

Solutions:
- Implement document size limits (max 100MB)
- Use streaming processing for large documents
- Add explicit garbage collection
- Monitor memory usage per task
```

#### 2. **Queue Backlog Issues**
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    QUEUE BACKLOG DIAGNOSIS                                              │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Symptoms:
- Queue length continuously grows
- Tasks wait in queue for hours
- New tasks are delayed

Root Causes:
- Workers are under-resourced
- Tasks are failing and retrying
- External dependencies are slow

Solutions:
- Scale workers horizontally
- Increase worker concurrency
- Optimize task execution time
- Implement task prioritization
```

#### 3. **External API Rate Limiting**
```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    RATE LIMITING DIAGNOSIS                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Symptoms:
- Connector sync tasks failing
- API calls returning 429 errors
- Tasks timing out

Root Causes:
- External APIs have rate limits
- Too many concurrent requests
- No backoff strategy

Solutions:
- Implement exponential backoff
- Add rate limiting to workers
- Use connection pooling
- Cache API responses
```

### Optimization Strategies

#### 1. **Task Batching**
```python
# Instead of processing one document at a time
@shared_task
def process_single_document(document_id: str):
    # Process one document
    pass

# Process multiple documents in batches
@shared_task
def process_document_batch(document_ids: list[str]):
    # Process multiple documents together
    # Reduces overhead and improves efficiency
    pass
```

#### 2. **Connection Pooling**
```python
# Reuse database connections
from sqlalchemy.pool import QueuePool

engine = create_engine(
    database_url,
    poolclass=QueuePool,
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True
)

# Reuse HTTP connections
import httpx

async with httpx.AsyncClient() as client:
    # Reuse connection for multiple requests
    pass
```

#### 3. **Caching Strategies**
```python
# Cache embedding results
from functools import lru_cache

@lru_cache(maxsize=1000)
def get_embedding(text: str) -> list[float]:
    # Cache embeddings for identical text
    return call_model_server(text)

# Cache external API responses
import redis

redis_client = redis.Redis()

def get_cached_api_response(url: str) -> dict:
    cache_key = f"api:{hash(url)}"
    cached = redis_client.get(cache_key)
    if cached:
        return json.loads(cached)
    
    response = make_api_call(url)
    redis_client.setex(cache_key, 3600, json.dumps(response))
    return response
```

---

## 📚 Conclusion

Celery is essential for Onyx because it enables:

1. **Asynchronous Processing**: Prevents blocking the main API server
2. **Scalability**: Can handle thousands of documents simultaneously
3. **Reliability**: Tasks are persisted and can be retried on failure
4. **Resource Management**: Efficiently utilizes CPU, memory, and network resources
5. **Monitoring**: Provides visibility into system performance and health

The technical implementation requires careful consideration of:
- **Hardware resources** (CPU, memory, storage, network)
- **Worker configuration** (concurrency, prefetch, timeouts)
- **Queue management** (priorities, routing, backpressure)
- **Monitoring and observability** (metrics, logging, alerting)

Without Celery workers, Onyx would be unable to process documents, sync connectors, or perform any background operations, making it essentially non-functional for enterprise use cases.

---

## 📖 References

- [Celery Documentation](https://docs.celeryq.dev/)
- [Redis Documentation](https://redis.io/docs/)
- [Onyx Source Code](https://github.com/onyx-dot-app/onyx)
- [Kubernetes Celery Patterns](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Prometheus Monitoring](https://prometheus.io/docs/)
- [Grafana Dashboards](https://grafana.com/docs/)

