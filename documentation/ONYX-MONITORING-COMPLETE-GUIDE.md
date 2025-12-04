# Onyx Monitoring Complete Guide

## 🎯 Executive Summary

This guide provides a **comprehensive monitoring solution** for Onyx deployments. It covers multiple monitoring approaches, from basic health checks to advanced observability with Prometheus, Grafana, and custom metrics.

**Yes, you can absolutely implement monitoring for Onyx!** This guide shows you how.

---

## 📊 Table of Contents

1. [Monitoring Possibilities Overview](#monitoring-possibilities-overview)
2. [What's Already Available in Onyx](#whats-already-available-in-onyx)
3. [Monitoring Architecture](#monitoring-architecture)
4. [Solution 1: Prometheus + Grafana (Recommended)](#solution-1-prometheus--grafana-recommended)
5. [Solution 2: Kubernetes Native Monitoring](#solution-2-kubernetes-native-monitoring)
6. [Solution 3: Custom Metrics Collection](#solution-3-custom-metrics-collection)
7. [Solution 4: Log-Based Monitoring](#solution-4-log-based-monitoring)
8. [Solution 5: Application Performance Monitoring (APM)](#solution-5-application-performance-monitoring-apm)
9. [Key Metrics to Monitor](#key-metrics-to-monitor)
10. [Dashboard Examples](#dashboard-examples)
11. [Alerting Rules](#alerting-rules)
12. [Implementation Steps](#implementation-steps)
13. [Best Practices](#best-practices)

---

## 🔍 Monitoring Possibilities Overview

### Available Monitoring Solutions

| Solution | Complexity | Cost | Best For | Features |
|----------|-----------|------|----------|----------|
| **Prometheus + Grafana** | Medium | Free (Open Source) | Production deployments | Metrics, dashboards, alerting |
| **Kubernetes Metrics** | Low | Free | Basic monitoring | CPU, memory, pod status |
| **Custom Metrics** | High | Free | Specific use cases | Custom business metrics |
| **ELK Stack** | High | Free/Paid | Log analysis | Log aggregation, search |
| **Datadog/New Relic** | Low | Paid | Enterprise | Full-stack APM |
| **Sentry** | Low | Free/Paid | Error tracking | Error monitoring, performance |

### Recommended Approach for 50 Users

**Primary**: Prometheus + Grafana (comprehensive, free, production-ready)  
**Secondary**: Kubernetes native metrics (basic resource monitoring)  
**Optional**: Sentry (error tracking - already integrated in Onyx)

---

## ✅ What's Already Available in Onyx

### 1. Built-in Monitoring Infrastructure

Onyx already includes several monitoring components:

#### A. Prometheus Client
- **Status**: ✅ Already installed
- **Location**: `backend/requirements/default.txt`
- **Package**: `prometheus_client==0.21.0`, `prometheus_fastapi_instrumentator==7.1.0`
- **Endpoint**: `/metrics` (exposed on API server)

#### B. Health Check Endpoints
- **Status**: ✅ Already available
- **Endpoints**:
  - `/health` - Basic health check
  - `/metrics` - Prometheus metrics
  - `/version` - Version information
- **Model Server**: `/api/health` - Model server health

#### C. Monitoring Celery Worker
- **Status**: ✅ Already configured
- **Location**: `backend/onyx/background/celery/tasks/monitoring/tasks.py`
- **Tasks**:
  - `MONITOR_BACKGROUND_PROCESSES` - Collects queue metrics, connector metrics
  - `MONITOR_CELERY_QUEUES` - Monitors all Celery queue lengths
- **Queue**: `monitoring`

#### D. Metrics Collection
- **Status**: ✅ Already implemented
- **Metrics Collected**:
  - Queue lengths for all Celery queues
  - Connector run metrics (start latency, success rate)
  - Sync speed metrics
  - Worker status and task counts
  - Memory usage

### 2. Current Monitoring Capabilities

```python
# Already available metrics (from monitoring tasks)
- Queue lengths: docprocessing, docfetching, user_file_processing, etc.
- Connector metrics: start latency, success rate
- Sync metrics: sync speed, completion time
- Worker metrics: memory usage, task counts
```

---

## 🏗️ Monitoring Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    ONYX MONITORING ARCHITECTURE                 │
└─────────────────────────────────────────────────────────────────┘

┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   Onyx API   │    │   Celery     │    │   Model      │
│   Server     │    │   Workers    │    │   Server     │
│              │    │              │    │              │
│  /metrics    │    │  Monitoring  │    │  /api/health │
│  /health     │    │  Tasks       │    │              │
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                   │                   │
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │
                           │ Metrics
                           │
                  ┌────────▼────────┐
                  │   Prometheus    │
                  │   (Scraper)     │
                  └────────┬─────────┘
                           │
                           │ Queries
                           │
                  ┌────────▼────────┐
                  │    Grafana      │
                  │  (Dashboards)   │
                  └────────┬─────────┘
                           │
                           │ Alerts
                           │
                  ┌────────▼────────┐
                  │  Alertmanager  │
                  │  (Notifications)│
                  └─────────────────┘
```

---

## 🚀 Solution 1: Prometheus + Grafana (Recommended)

### Overview

**Prometheus** collects and stores metrics, **Grafana** visualizes them in dashboards. This is the **industry standard** for Kubernetes monitoring.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│              PROMETHEUS + GRAFANA SETUP                         │
└─────────────────────────────────────────────────────────────────┘

Components:
1. Prometheus Server - Scrapes metrics from Onyx
2. Grafana - Visualizes metrics in dashboards
3. ServiceMonitor - Tells Prometheus what to scrape
4. Alertmanager - Sends alerts (optional)
```

### Step 1: Install Prometheus Operator

**For OpenShift/Kubernetes**:

```bash
# Install Prometheus Operator (if not already installed)
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml

# Or use Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace
```

### Step 2: Create ServiceMonitor for Onyx API Server

**File**: `manifests/monitoring/onyx-api-servicemonitor.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: onyx-api-server
  namespace: onyx  # Your Onyx namespace
  labels:
    app: onyx-api-server
spec:
  selector:
    matchLabels:
      app: onyx-api-server
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
```

**Apply**:
```bash
kubectl apply -f manifests/monitoring/onyx-api-servicemonitor.yaml
```

### Step 3: Create ServiceMonitor for Model Server

**File**: `manifests/monitoring/onyx-model-server-servicemonitor.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: onyx-model-server
  namespace: onyx
  labels:
    app: onyx-model-server
spec:
  selector:
    matchLabels:
      app: onyx-model-server
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

### Step 4: Expose Metrics Endpoint in Service

**Ensure your Service exposes the metrics port**:

```yaml
# In your onyx-api-server service
apiVersion: v1
kind: Service
metadata:
  name: onyx-api-server
spec:
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: metrics  # Add metrics port
      port: 8080
      targetPort: 8080
  selector:
    app: onyx-api-server
```

### Step 5: Install Grafana

**Using Helm**:
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana \
  --namespace monitoring \
  --set persistence.enabled=true \
  --set adminPassword=admin
```

**Or use the Grafana from Prometheus Operator**:
```bash
# Grafana is included in kube-prometheus-stack
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Access at http://localhost:3000 (admin/prom-operator)
```

### Step 6: Access Grafana

```bash
# Get Grafana admin password
kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d

# Port forward
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Access at http://localhost:3000
# Username: admin
# Password: (from above)
```

### Step 7: Create Grafana Dashboards

See [Dashboard Examples](#dashboard-examples) section below for ready-to-use dashboards.

---

## 🎯 Solution 2: Kubernetes Native Monitoring

### Overview

Use built-in Kubernetes metrics without additional tools.

### Available Metrics

```bash
# CPU and Memory usage
kubectl top pods -n onyx

# Node metrics
kubectl top nodes

# Pod resource usage
kubectl describe pod <pod-name> -n onyx
```

### Kubernetes Metrics API

```bash
# Check if metrics server is installed
kubectl get apiservice v1beta1.metrics.k8s.io

# View pod metrics
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/onyx/pods
```

### Dashboard: Kubernetes Dashboard

```bash
# Install Kubernetes Dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Create service account
kubectl create serviceaccount dashboard-admin -n kubernetes-dashboard
kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:dashboard-admin

# Get token
kubectl -n kubernetes-dashboard create token dashboard-admin

# Access
kubectl proxy
# Open http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

---

## 📊 Solution 3: Custom Metrics Collection

### Overview

Collect custom business metrics specific to Onyx operations.

### A. Celery Queue Metrics

**File**: `manifests/monitoring/celery-queue-exporter.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: celery-queue-exporter
  namespace: onyx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: celery-queue-exporter
  template:
    metadata:
      labels:
        app: celery-queue-exporter
    spec:
      containers:
        - name: exporter
          image: python:3.11
          command:
            - python
            - -c
            - |
              from redis import Redis
              from prometheus_client import Gauge, start_http_server
              import time
              
              redis_client = Redis(host='redis', port=6379)
              
              queue_length = Gauge('celery_queue_length', 'Queue length', ['queue_name'])
              
              def collect_metrics():
                  queues = [
                      'docprocessing',
                      'docfetching',
                      'user_file_processing',
                      'monitoring'
                  ]
                  for queue in queues:
                      length = redis_client.llen(f'celery:{queue}')
                      queue_length.labels(queue_name=queue).set(length)
              
              start_http_server(8000)
              while True:
                  collect_metrics()
                  time.sleep(30)
          ports:
            - containerPort: 8000
              name: metrics
```

### B. Database Metrics

**File**: `manifests/monitoring/postgres-exporter.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  namespace: onyx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-exporter
  template:
    metadata:
      labels:
        app: postgres-exporter
    spec:
      containers:
        - name: exporter
          image: prometheuscommunity/postgres-exporter:latest
          env:
            - name: DATA_SOURCE_NAME
              value: "postgresql://user:password@postgres:5432/onyx?sslmode=disable"
          ports:
            - containerPort: 9187
              name: metrics
```

### C. Redis Metrics

**File**: `manifests/monitoring/redis-exporter.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-exporter
  namespace: onyx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-exporter
  template:
    metadata:
      labels:
        app: redis-exporter
    spec:
      containers:
        - name: exporter
          image: oliver006/redis_exporter:latest
          env:
            - name: REDIS_ADDR
              value: "redis:6379"
          ports:
            - containerPort: 9121
              name: metrics
```

---

## 📝 Solution 4: Log-Based Monitoring

### Overview

Monitor Onyx through log analysis.

### A. ELK Stack (Elasticsearch, Logstash, Kibana)

**Installation**:
```bash
helm repo add elastic https://helm.elastic.co
helm install elasticsearch elastic/elasticsearch
helm install logstash elastic/logstash
helm install kibana elastic/kibana
```

**Collect Onyx Logs**:
```yaml
# Filebeat configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: filebeat-config
data:
  filebeat.yml: |
    filebeat.inputs:
      - type: container
        paths:
          - /var/log/containers/onyx-*.log
    output.elasticsearch:
      hosts: ["elasticsearch:9200"]
```

### B. Loki + Grafana (Lightweight)

**Installation**:
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack
```

**Query Logs in Grafana**:
```logql
# Onyx API errors
{namespace="onyx", container="onyx-api-server"} |= "ERROR"

# Celery task failures
{namespace="onyx", container="celery-worker"} |= "FAILED"
```

---

## 🔬 Solution 5: Application Performance Monitoring (APM)

### A. Sentry (Already Integrated)

**Status**: ✅ Already in Onyx  
**Location**: `web/next.config.js`, `web/sentry.*.config.ts`

**Configuration**:
```javascript
// Already configured in Onyx
Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: process.env.NODE_ENV,
  tracesSampleRate: 1.0,
});
```

**Access**: https://sentry.io (if configured)

### B. Datadog

**Installation**:
```bash
helm repo add datadog https://helm.datadoghq.com
helm install datadog-agent datadog/datadog \
  --set datadog.apiKey=YOUR_API_KEY \
  --set datadog.site=datadoghq.com
```

### C. New Relic

**Installation**:
```yaml
# Add New Relic agent to Onyx containers
env:
  - name: NEW_RELIC_LICENSE_KEY
    value: "YOUR_LICENSE_KEY"
  - name: NEW_RELIC_APP_NAME
    value: "onyx"
```

---

## 📈 Key Metrics to Monitor

### 1. Application Metrics

#### API Server Metrics

```promql
# Request rate
rate(http_requests_total[5m])

# Request latency (p95)
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Error rate
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# Active users
active_sessions_total
```

#### Celery Worker Metrics

```promql
# Queue length
celery_queue_length{queue_name="user_file_processing"}

# Task completion rate
rate(celery_tasks_total{status="success"}[5m])

# Task failure rate
rate(celery_tasks_total{status="failed"}[5m]) / rate(celery_tasks_total[5m])

# Task duration
histogram_quantile(0.95, celery_task_duration_seconds_bucket)
```

#### Model Server Metrics

```promql
# Embedding generation rate
rate(embedding_requests_total[5m])

# Embedding latency
histogram_quantile(0.95, embedding_duration_seconds_bucket)

# Model server CPU
process_cpu_seconds_total{job="onyx-model-server"}

# Model server memory
process_resident_memory_bytes{job="onyx-model-server"}
```

### 2. Infrastructure Metrics

#### Kubernetes Metrics

```promql
# Pod CPU usage
rate(container_cpu_usage_seconds_total[5m])

# Pod memory usage
container_memory_working_set_bytes

# Pod restarts
kube_pod_container_status_restarts_total

# Pod status
kube_pod_status_phase
```

#### Database Metrics

```promql
# Database connections
pg_stat_database_numbackends

# Query duration
pg_stat_statements_mean_exec_time

# Database size
pg_database_size_bytes
```

#### Redis Metrics

```promql
# Redis memory
redis_memory_used_bytes

# Redis connections
redis_connected_clients

# Redis operations
rate(redis_commands_processed_total[5m])
```

### 3. Business Metrics

#### Document Processing

```promql
# Documents processed per hour
rate(documents_processed_total[1h]) * 3600

# Average processing time
histogram_quantile(0.50, document_processing_duration_seconds_bucket)

# Processing success rate
rate(documents_processed_total{status="success"}[5m]) / rate(documents_processed_total[5m])
```

#### User File Upload

```promql
# File upload rate
rate(user_files_uploaded_total[5m])

# Upload success rate
rate(user_files_uploaded_total{status="success"}[5m]) / rate(user_files_uploaded_total[5m])

# Average upload time
histogram_quantile(0.95, user_file_upload_duration_seconds_bucket)
```

#### Search Performance

```promql
# Search request rate
rate(search_requests_total[5m])

# Search latency
histogram_quantile(0.95, search_duration_seconds_bucket)

# Search success rate
rate(search_requests_total{status="success"}[5m]) / rate(search_requests_total[5m])
```

---

## 📊 Dashboard Examples

### Dashboard 1: Onyx Overview

**Grafana Dashboard JSON**: See `manifests/monitoring/grafana-dashboards/onyx-overview.json`

**Panels**:
1. **Request Rate** - HTTP requests per second
2. **Error Rate** - Percentage of failed requests
3. **Response Time** - P50, P95, P99 latency
4. **Active Users** - Current active sessions
5. **Queue Lengths** - All Celery queue lengths
6. **Worker Status** - Celery worker health
7. **Resource Usage** - CPU, memory per pod

### Dashboard 2: Celery Workers

**Panels**:
1. **Queue Length by Queue** - Bar chart
2. **Task Completion Rate** - Line chart
3. **Task Duration** - Histogram
4. **Worker Memory Usage** - Time series
5. **Failed Tasks** - Table with error messages

### Dashboard 3: Document Processing

**Panels**:
1. **Documents Processed/Hour** - Counter
2. **Processing Time Distribution** - Histogram
3. **Processing Success Rate** - Gauge
4. **Chunks Generated** - Time series
5. **Embedding Generation Time** - Line chart

### Dashboard 4: Model Server

**Panels**:
1. **Embedding Requests/sec** - Rate
2. **Embedding Latency** - P95 latency
3. **Model Server CPU** - Usage percentage
4. **Model Server Memory** - Usage in GB
5. **Batch Size Distribution** - Histogram

### Creating Dashboards

**Method 1: Import JSON**
```bash
# In Grafana UI:
# 1. Go to Dashboards → Import
# 2. Upload JSON file
# 3. Select Prometheus data source
# 4. Save dashboard
```

**Method 2: Create Manually**
```bash
# In Grafana UI:
# 1. Create new dashboard
# 2. Add panel
# 3. Select Prometheus data source
# 4. Enter PromQL query
# 5. Configure visualization
```

---

## 🚨 Alerting Rules

### Prometheus Alert Rules

**File**: `manifests/monitoring/prometheus-rules.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: onyx-alerts
  namespace: onyx
spec:
  groups:
    - name: onyx.rules
      interval: 30s
      rules:
        # High error rate
        - alert: OnyxHighErrorRate
          expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Onyx API has high error rate"
            description: "Error rate is {{ $value | humanizePercentage }}"

        # Queue backlog
        - alert: OnyxQueueBacklog
          expr: celery_queue_length{queue_name="user_file_processing"} > 100
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Celery queue has high backlog"
            description: "Queue {{ $labels.queue_name }} has {{ $value }} pending tasks"

        # Worker down
        - alert: OnyxWorkerDown
          expr: up{job="celery-worker"} == 0
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: "Celery worker is down"
            description: "Worker {{ $labels.instance }} is not responding"

        # High memory usage
        - alert: OnyxHighMemoryUsage
          expr: container_memory_working_set_bytes{pod=~"onyx-.*"} / container_spec_memory_limit_bytes > 0.9
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Pod has high memory usage"
            description: "Pod {{ $labels.pod }} is using {{ $value | humanizePercentage }} memory"

        # Model server slow
        - alert: OnyxModelServerSlow
          expr: histogram_quantile(0.95, embedding_duration_seconds_bucket) > 2
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Model server is slow"
            description: "P95 embedding latency is {{ $value }}s"

        # Database connections high
        - alert: OnyxDatabaseConnectionsHigh
          expr: pg_stat_database_numbackends > 80
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Database has high connection count"
            description: "{{ $value }} database connections in use"
```

**Apply**:
```bash
kubectl apply -f manifests/monitoring/prometheus-rules.yaml
```

### Alertmanager Configuration

**File**: `manifests/monitoring/alertmanager-config.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-config
  namespace: monitoring
type: Opaque
stringData:
  alertmanager.yml: |
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'severity']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 12h
      receiver: 'default'
      routes:
        - match:
            severity: critical
          receiver: 'critical-alerts'
    receivers:
      - name: 'default'
        email_configs:
          - to: 'admin@example.com'
            from: 'alertmanager@example.com'
            smarthost: 'smtp.example.com:587'
            auth_username: 'alertmanager'
            auth_password: 'password'
      - name: 'critical-alerts'
        email_configs:
          - to: 'oncall@example.com'
        slack_configs:
          - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
            channel: '#alerts'
            title: 'Critical Alert: {{ .GroupLabels.alertname }}'
```

---

## 🛠️ Implementation Steps

### Step-by-Step Guide

#### Phase 1: Basic Monitoring (Week 1)

1. **Verify existing metrics**:
   ```bash
   # Check if /metrics endpoint works
   curl http://onyx-api-server:8080/metrics
   ```

2. **Install Prometheus Operator**:
   ```bash
   helm install prometheus prometheus-community/kube-prometheus-stack \
     --namespace monitoring --create-namespace
   ```

3. **Create ServiceMonitors**:
   ```bash
   kubectl apply -f manifests/monitoring/onyx-api-servicemonitor.yaml
   kubectl apply -f manifests/monitoring/onyx-model-server-servicemonitor.yaml
   ```

4. **Access Grafana**:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
   ```

#### Phase 2: Custom Metrics (Week 2)

1. **Deploy custom exporters**:
   ```bash
   kubectl apply -f manifests/monitoring/celery-queue-exporter.yaml
   kubectl apply -f manifests/monitoring/postgres-exporter.yaml
   kubectl apply -f manifests/monitoring/redis-exporter.yaml
   ```

2. **Create ServiceMonitors for exporters**:
   ```bash
   kubectl apply -f manifests/monitoring/exporter-servicemonitors.yaml
   ```

#### Phase 3: Dashboards (Week 3)

1. **Import dashboards**:
   - Onyx Overview Dashboard
   - Celery Workers Dashboard
   - Document Processing Dashboard
   - Model Server Dashboard

2. **Customize dashboards** for your needs

#### Phase 4: Alerting (Week 4)

1. **Create alert rules**:
   ```bash
   kubectl apply -f manifests/monitoring/prometheus-rules.yaml
   ```

2. **Configure Alertmanager**:
   ```bash
   kubectl apply -f manifests/monitoring/alertmanager-config.yaml
   ```

3. **Test alerts**:
   - Trigger test alert
   - Verify notification delivery

---

## ✅ Best Practices

### 1. Metric Naming

**Follow Prometheus conventions**:
- Use `_total` suffix for counters
- Use `_seconds` suffix for durations
- Use `_bytes` suffix for sizes
- Use descriptive labels

**Good**:
```
http_requests_total{method="GET", endpoint="/api/chat", status="200"}
celery_task_duration_seconds{worker="docprocessing", task="index_document"}
```

**Bad**:
```
requests
task_time
```

### 2. Dashboard Design

- **Keep dashboards focused** - One dashboard per component
- **Use appropriate visualizations** - Line charts for time series, gauges for current values
- **Add descriptions** - Explain what each panel shows
- **Set refresh intervals** - Auto-refresh every 30s-1m

### 3. Alerting

- **Avoid alert fatigue** - Only alert on actionable issues
- **Use severity levels** - warning vs critical
- **Set appropriate thresholds** - Based on actual baseline
- **Test alerts** - Verify they fire and resolve correctly

### 4. Resource Management

- **Limit metric cardinality** - Don't create too many unique label combinations
- **Set retention policies** - Keep metrics for appropriate time (30-90 days)
- **Monitor Prometheus itself** - Ensure it has enough resources

### 5. Security

- **Secure metrics endpoints** - Use authentication if exposing publicly
- **Network policies** - Restrict access to Prometheus
- **RBAC** - Limit who can view/modify monitoring resources

---

## 📋 Monitoring Checklist

### Daily Checks

- [ ] Review error rates
- [ ] Check queue lengths
- [ ] Verify worker health
- [ ] Monitor resource usage

### Weekly Reviews

- [ ] Analyze performance trends
- [ ] Review alert history
- [ ] Update dashboards if needed
- [ ] Check metric retention

### Monthly Reviews

- [ ] Capacity planning based on metrics
- [ ] Review and optimize alert rules
- [ ] Update documentation
- [ ] Performance optimization

---

## 🔗 Related Documentation

- [Complete Indexing Performance Optimization Guide](./COMPLETE-INDEXING-PERFORMANCE-OPTIMIZATION-GUIDE.md)
- [Celery Workers Architecture](./CELERY-WORKERS-ARCHITECTURE-DIAGRAM.md)
- [File Upload Performance Optimization](./FILE-UPLOAD-PERFORMANCE-OPTIMIZATION.md)
- [Single vs Multiple Document Indexing](./SINGLE-VS-MULTIPLE-DOCUMENT-INDEXING-GUIDE.md)

---

## 📚 Additional Resources

- **Prometheus Documentation**: https://prometheus.io/docs/
- **Grafana Documentation**: https://grafana.com/docs/
- **Prometheus Operator**: https://github.com/prometheus-operator/prometheus-operator
- **PromQL Guide**: https://prometheus.io/docs/prometheus/latest/querying/basics/

---

**Last Updated**: 2024  
**Author**: Onyx Deployment Team  
**Version**: 1.0

