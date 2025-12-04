# Onyx Monitoring Manifests

This directory contains Kubernetes manifests for monitoring Onyx deployments.

## Files

- `onyx-api-servicemonitor.yaml` - ServiceMonitor for Onyx API Server metrics
- `onyx-model-server-servicemonitor.yaml` - ServiceMonitor for Model Server metrics
- `prometheus-rules.yaml` - Prometheus alerting rules for Onyx

## Usage

### Prerequisites

1. Prometheus Operator installed in your cluster
2. Prometheus instance configured to discover ServiceMonitors

### Installation

1. **Update namespace** in all YAML files to match your Onyx namespace

2. **Apply ServiceMonitors**:
   ```bash
   kubectl apply -f onyx-api-servicemonitor.yaml
   kubectl apply -f onyx-model-server-servicemonitor.yaml
   ```

3. **Apply Alert Rules**:
   ```bash
   kubectl apply -f prometheus-rules.yaml
   ```

4. **Verify**:
   ```bash
   # Check ServiceMonitors
   kubectl get servicemonitor -n onyx
   
   # Check PrometheusRules
   kubectl get prometheusrule -n onyx
   
   # Check if Prometheus is scraping
   # In Prometheus UI: Status → Targets
   ```

## Customization

### ServiceMonitor

- **interval**: How often to scrape (default: 30s)
- **scrapeTimeout**: Timeout for scraping (default: 10s)
- **path**: Metrics endpoint path (default: /metrics)

### Alert Rules

- **thresholds**: Adjust based on your baseline metrics
- **for**: Duration before alert fires
- **severity**: warning or critical

## Troubleshooting

### Metrics not appearing

1. Check if `/metrics` endpoint is accessible:
   ```bash
   kubectl port-forward svc/onyx-api-server 8080:8080
   curl http://localhost:8080/metrics
   ```

2. Check ServiceMonitor labels match Service labels:
   ```bash
   kubectl get svc onyx-api-server -o yaml | grep labels
   kubectl get servicemonitor onyx-api-server -o yaml | grep matchLabels
   ```

3. Check Prometheus targets:
   - Access Prometheus UI
   - Go to Status → Targets
   - Look for "onyx-api-server" target
   - Check if it's UP and scraping

### Alerts not firing

1. Check PrometheusRule is loaded:
   ```bash
   kubectl get prometheusrule onyx-alerts -o yaml
   ```

2. Test alert expression in Prometheus:
   - Go to Prometheus UI
   - Enter alert expression
   - Check if it returns data

3. Check Alertmanager configuration:
   ```bash
   kubectl get secret alertmanager-main -n monitoring -o yaml
   ```

## Additional Resources

See [ONYX-MONITORING-COMPLETE-GUIDE.md](../documentation/ONYX-MONITORING-COMPLETE-GUIDE.md) for complete monitoring setup instructions.

