# Troubleshooting Guides

Common issues and their solutions for Onyx Kubernetes deployment.

---

## 🆘 Quick Help

### I can't access Onyx!
→ [STEP-BY-STEP-FIX.md](STEP-BY-STEP-FIX.md)

### NGINX connection timeout errors
→ [NGINX-DNS-TROUBLESHOOTING-GUIDE.md](NGINX-DNS-TROUBLESHOOTING-GUIDE.md)
→ [MISSING-SERVICES-SOLUTION.md](MISSING-SERVICES-SOLUTION.md)

### DNS resolution failures
→ [FULL-DNS-RESOLUTION-FIX.md](FULL-DNS-RESOLUTION-FIX.md)
→ [OPENSHIFT-DNS-RESOLUTION-FIX.md](OPENSHIFT-DNS-RESOLUTION-FIX.md)

### Resource quota errors
→ [OPENSHIFT-RESOURCE-QUOTA-FIX.md](OPENSHIFT-RESOURCE-QUOTA-FIX.md)

### NGINX errors
→ [NGINX-UPSTREAM-ERROR-ANALYSIS.md](NGINX-UPSTREAM-ERROR-ANALYSIS.md)
→ [NGINX-CONFIGMAP-ISSUE-ANALYSIS.md](NGINX-CONFIGMAP-ISSUE-ANALYSIS.md)

---

## 📋 All Troubleshooting Guides

### General Issues

#### [STEP-BY-STEP-FIX.md](STEP-BY-STEP-FIX.md)
**Problem:** General deployment issues
**Contents:**
- Check current deployment status
- Deploy missing services
- Verify service endpoints
- Test connectivity
- Complete checklist

**Start here** if you're not sure what's wrong!

---

### NGINX Issues

#### [NGINX-DNS-TROUBLESHOOTING-GUIDE.md](NGINX-DNS-TROUBLESHOOTING-GUIDE.md)
**Problem:** NGINX can't resolve service names
**Contents:**
- Debugging steps
- Multiple solution options
- Hardcoded namespace approach
- Verification commands

#### [NGINX-UPSTREAM-ERROR-ANALYSIS.md](NGINX-UPSTREAM-ERROR-ANALYSIS.md)
**Problem:** "host not found in upstream" error
**Root Cause:** NGINX starting before services
**Solution:** Deployment order, initContainer

#### [NGINX-CONFIGMAP-ISSUE-ANALYSIS.md](NGINX-CONFIGMAP-ISSUE-ANALYSIS.md)
**Problem:** NGINX ConfigMap mounting issues
**Root Cause:** Overwriting default nginx.conf
**Solution:** Mount to /etc/nginx/conf.d/default.conf

---

### DNS Resolution Issues

#### [FULL-DNS-RESOLUTION-FIX.md](FULL-DNS-RESOLUTION-FIX.md)
**Problem:** Services can't be resolved by DNS
**Contents:**
- Full DNS name format
- Dynamic namespace resolution
- Environment variable setup
- Testing procedures

#### [OPENSHIFT-DNS-RESOLUTION-FIX.md](OPENSHIFT-DNS-RESOLUTION-FIX.md)
**Problem:** OpenShift-specific DNS issues
**Root Cause:** Stricter DNS resolution in OpenShift
**Solution:** Full FQDN names, initContainer waits

---

### Service Issues

#### [MISSING-SERVICES-SOLUTION.md](MISSING-SERVICES-SOLUTION.md)
**Problem:** Services don't exist or have no endpoints
**Root Cause:** Services not created or pods not running
**Solution:**
- Create service definitions
- Check pod labels match service selectors
- Verify deployments are running

#### [WEBSERVER-DEPLOYMENT-ANALYSIS.md](WEBSERVER-DEPLOYMENT-ANALYSIS.md)
**Problem:** Web server deployment analysis
**Contents:**
- Deployment structure review
- Service definition requirements
- Label matching

---

### OpenShift-Specific Issues

#### [OPENSHIFT-RESOURCE-QUOTA-FIX.md](OPENSHIFT-RESOURCE-QUOTA-FIX.md)
**Problem:** "must specify limits.cpu/memory" errors
**Root Cause:** OpenShift requires resource limits on all containers
**Solution:** Add requests and limits to all containers and initContainers

---

## 🔍 Common Error Messages

### "host not found in upstream"
→ [NGINX-UPSTREAM-ERROR-ANALYSIS.md](NGINX-UPSTREAM-ERROR-ANALYSIS.md)
→ [MISSING-SERVICES-SOLUTION.md](MISSING-SERVICES-SOLUTION.md)

### "connection timeout"
→ [STEP-BY-STEP-FIX.md](STEP-BY-STEP-FIX.md)
→ [NGINX-DNS-TROUBLESHOOTING-GUIDE.md](NGINX-DNS-TROUBLESHOOTING-GUIDE.md)

### "nslookup: can't resolve"
→ [FULL-DNS-RESOLUTION-FIX.md](FULL-DNS-RESOLUTION-FIX.md)
→ [OPENSHIFT-DNS-RESOLUTION-FIX.md](OPENSHIFT-DNS-RESOLUTION-FIX.md)

### "failed quota: must specify limits"
→ [OPENSHIFT-RESOURCE-QUOTA-FIX.md](OPENSHIFT-RESOURCE-QUOTA-FIX.md)

### "service has no endpoints"
→ [MISSING-SERVICES-SOLUTION.md](MISSING-SERVICES-SOLUTION.md)

---

## 🛠️ Debugging Commands

### Check Service Status
```bash
# List all services
oc get services

# Check specific service
oc get service web-server

# Check service endpoints
oc get endpoints web-server

# If no endpoints, check pod labels
oc get pods --show-labels
```

### Test DNS Resolution
```bash
# From NGINX pod
oc exec deployment/nginx -- nslookup web-server
oc exec deployment/nginx -- nslookup api-server

# Test with full DNS name
oc exec deployment/nginx -- nslookup web-server.$(oc project -q).svc.cluster.local
```

### Test Connectivity
```bash
# Test HTTP connection
oc exec deployment/nginx -- curl http://web-server:3000
oc exec deployment/nginx -- curl http://api-server:8080

# Test with wget
oc exec deployment/nginx -- wget -O- http://web-server:3000
```

### Check Logs
```bash
# NGINX logs
oc logs deployment/nginx

# InitContainer logs
oc logs deployment/nginx -c wait-for-services

# API server logs
oc logs deployment/api-server

# Web server logs
oc logs deployment/web-server
```

### Check Pod Status
```bash
# List all pods
oc get pods

# Describe pod for events
oc describe pod <pod-name>

# Check pod labels
oc get pods --show-labels

# Check if pod is ready
oc get pods -l app=nginx
```

---

## 📊 Troubleshooting Flowchart

```
Issue: Can't access Onyx
        ↓
    Check pods running?
    ├─ No → Check deployment YAML
    └─ Yes → Check services exist?
            ├─ No → Deploy services
            └─ Yes → Check service endpoints?
                    ├─ No endpoints → Check pod labels
                    └─ Has endpoints → Check NGINX logs
                                      ↓
                              DNS resolution issue?
                              ├─ Yes → DNS troubleshooting guide
                              └─ No → Check route/network policies
```

---

## 🔗 Quick Links

- **Main README:** [../README.md](../README.md)
- **Manifests:** [../manifests/](../manifests/)
- **Documentation:** [../documentation/](../documentation/)
- **Guides:** [../guides/](../guides/)

---

## 💡 Tips

1. **Always check in this order:**
   - Pods running?
   - Services exist?
   - Services have endpoints?
   - DNS resolves?
   - Network connectivity?

2. **Use describe for details:**
   ```bash
   oc describe pod <pod-name>
   oc describe service <service-name>
   ```

3. **Check events:**
   ```bash
   oc get events --sort-by='.lastTimestamp'
   ```

4. **Test from inside cluster:**
   ```bash
   oc run debug --image=busybox:1.35 --rm -it -- sh
   ```

---

**If you can't find your issue here, check the main documentation or create an issue on GitHub!**
