# Kubernetes NetworkPolicies – A Practical Guide (Junior Friendly)

This guide explains Kubernetes NetworkPolicies from scratch and gives copy‑pasteable examples that match our Onyx minimal deployment (web → api → other services) on OpenShift.

---

## 1) What is a NetworkPolicy?
- A NetworkPolicy is a firewall rule at the Pod level.
- It tells the cluster which Pods are allowed to talk to which Pods (and which external IPs), on which ports, and in which direction: Ingress (incoming) or Egress (outgoing).
- NetworkPolicies are enforced by the cluster CNI (OpenShift SDN/OVN-K), not by Kubernetes itself.

Important: NetworkPolicies are label-based. Policies select:
- “Who is protected”: `spec.podSelector` (pods the policy applies to)
- “Who can talk to them / where they can talk to”: `ingress.from` and `egress.to` using `podSelector`, `namespaceSelector`, `ipBlock` and the `ports` list.

---

## 2) Default behavior
- If there are no NetworkPolicies in a namespace: all traffic is allowed (allow-all by default).
- The moment you create ANY NetworkPolicy that selects Pods, those selected Pods become DENY-ALL for the directions you specify, except what you explicitly allow in that policy set.
  - Example: create an egress policy for a Pod → egress is blocked by default for that Pod unless explicitly allowed by policies.

---

## 3) Key selectors (how you match things)
- `podSelector`: match Pods by labels, e.g. `app: api-server`.
- `namespaceSelector`: match namespaces by labels (OpenShift adds `kubernetes.io/metadata.name: <ns>`).
- `ipBlock`: allow/deny CIDR IP ranges (use for external networks).

Tip: Always verify the labels on your Deployments/Pods:
```bash
oc get deploy api-server -o jsonpath='{.spec.template.metadata.labels}'
```
Make your policy match these exact labels.

---

## 4) Common building blocks you almost always need

### 4.1 Allow DNS (cluster DNS is required for service discovery)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
spec:
  podSelector: {}              # applies to all pods in the namespace
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: openshift-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

### 4.2 Default deny for everything (start locked down)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```
Apply this only if you then add explicit allow policies (like the ones below), otherwise all traffic will be blocked.

---

## 5) Concrete Onyx examples

### 5.1 Allow web-server to talk to api-server on port 8080 (egress from web → ingress to api)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-to-api
spec:
  podSelector:
    matchLabels:
      app: web-server               # protect web-server pods
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: api-server       # destination pods
      ports:
        - protocol: TCP
          port: 8080
```
If you also enabled ingress restrictions on the API pods, add a companion policy:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-from-web-to-api
spec:
  podSelector:
    matchLabels:
      app: api-server               # protect api-server pods
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: web-server
      ports:
        - protocol: TCP
          port: 8080
```

### 5.2 Allow NGINX to web-server and api-server (reverse proxy paths)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx-egress
spec:
  podSelector:
    matchLabels:
      app: nginx
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: web-server
      ports:
        - protocol: TCP
          port: 3000
    - to:
        - podSelector:
            matchLabels:
              app: api-server
      ports:
        - protocol: TCP
          port: 8080
```
If you restrict ingress on web/api, add matching ingress policies for traffic from `app: nginx`.

### 5.3 Allow API server to database/redis/vespa
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-egress-backends
spec:
  podSelector:
    matchLabels:
      app: api-server
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector: { matchLabels: { app: postgresql } }
      ports:
        - protocol: TCP
          port: 5432
    - to:
        - podSelector: { matchLabels: { app: redis } }
      ports:
        - protocol: TCP
          port: 6379
    - to:
        - podSelector: { matchLabels: { app: vespa } }
      ports:
        - protocol: TCP
          port: 19071
```
Adjust labels/ports to your manifests.

### 5.4 Allow a dedicated test pod to call the API (your scenario)
If your test pod has label `io.kompose.helper: test` but your API pods use `app: api-server`, you must match that real label:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-test-to-api
spec:
  podSelector:
    matchLabels:
      io.kompose.helper: test
  policyTypes:
    - Egress
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: api-server
      ports:
        - protocol: TCP
          port: 8080
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: openshift-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

---

## 6) Service vs Pod: which to target?
- NetworkPolicies evaluate **Pods**, not Services. Even if you curl `api-server:8080` (Service), the policy must allow egress to the **Pods** behind that Service (matched by pod labels).
- A Service failing with `Connection refused` can mean:
  1) Endpoints list is empty (selector mismatch). Check:
     ```bash
     oc get endpoints api-server
     ```
  2) The Pod isn’t listening on the expected port. Check:
     ```bash
     oc logs deploy/api-server
     oc exec deploy/api-server -- ss -ltnp | grep 8080
     ```
  3) NetworkPolicy is blocking the traffic. Fix labels/ports in your policies.

---

## 7) Troubleshooting checklist
1. Labels
   - `oc get deploy <name> -o jsonpath='{.spec.template.metadata.labels}'` – do labels match your policy?
2. Endpoints
   - `oc get endpoints <service>` – do you see Pod IPs and the right port?
3. DNS
   - Add an egress DNS policy (section 4.1) so `web-server`, `api-server` names resolve.
4. Curl tests from inside the right pod
   - `oc exec -it deploy/nginx -- curl -v http://api-server:8080/health`
5. Describe policy decisions (OVN-K/NetworkPolicy logs can help on OpenShift if enabled).

---

## 8) Safe rollout approach
- Start with allow-all (no policies) → system works.
- Add `allow-dns-egress` first.
- Add **one** egress policy at a time (e.g., `allow-web-to-api`).
- Only after egress rules work, consider adding ingress restrictions.
- Optional: add `default-deny-all` last, when you’re sure all allow rules exist.

---

## 9) Quick reference
- `podSelector` = which pods are protected by this policy
- `ingress.from` / `egress.to` = who is allowed to talk
- Use **pod labels** that actually exist on your Deployments
- Always allow **DNS**
- Policies are **additive** – multiple policies can apply to the same pod

This guide should give you a solid foundation to design and debug NetworkPolicies in our Onyx/OpenShift deployments.

---

## (Bonus) Quick test: Postgres connectivity
From a test pod (or the `api-server` pod), run any of these:

```bash
# 1) Fast readiness check
oc exec -it deploy/api-server -- pg_isready -h postgresql -p 5432

# 2) TCP reachability only using curl (no nc in base images)
# curl exits 52 on bare TCP, so just check it reaches the socket
oc exec -it deploy/api-server -- sh -c "curl -sS --connect-timeout 3 http://postgresql:5432 || true"

# 3) Actual query (requires creds available as env)
oc exec -it deploy/api-server -- sh -c \
  "PGPASSWORD=$POSTGRES_PASSWORD psql -h postgresql -U $POSTGRES_USER -d $POSTGRES_DB -c 'select 1;'"
```
If these fail, check: endpoints for the `postgresql` Service, your egress NetworkPolicy to port 5432, and API pod logs.
