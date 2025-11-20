# Viewing Uploaded Documents in a Kubernetes Deployment

This guide shows how to inspect the Onyx database directly from a Kubernetes/OpenShift deployment to list uploaded documents. It assumes:

- You deployed Onyx using the `onyx-k8s-infrastructure` manifests.
- PostgreSQL runs inside the cluster as a pod (manifest `02-postgresql.yaml`).
- You have `kubectl` or `oc` access to the namespace.

---

## 1. Identify the PostgreSQL pod

List pods in the namespace (replace `onyx` with your namespace):

```bash
kubectl get pods -n onyx
# or
oc get pods -n onyx
```

Look for a pod named similar to `postgresql-0` (statefulset). Example output:

```
NAME                          READY   STATUS    RESTARTS   AGE
api-server-6f4d8bbf75-h7k4m   1/1     Running   0          2d
postgresql-0                  1/1     Running   0          2d
vespa-0                       1/1     Running   0          2d
```

Note the pod name (`postgresql-0`).

---

## 2. Exec into the PostgreSQL pod

Use `kubectl exec` (or `oc exec`) to open a shell inside the pod:

```bash
kubectl exec -it postgresql-0 -n onyx -- /bin/bash
# or
oc exec -it postgresql-0 -n onyx -- /bin/bash
```

Inside the pod you should see the PostgreSQL tools installed (e.g., `/usr/bin/psql`).

---

## 3. Connect to the database

The default database/user values in the manifests (`02-postgresql.yaml`) are:

- Database: `postgres`
- User: `postgres`
- Password: stored in Kubernetes secret `postgresql-secret`

Retrieve the password (back on your local shell):

```bash
kubectl get secret postgresql-secret -n onyx -o jsonpath='{.data.postgres-password}' | base64 -d
# Example output: mysupersecret
```

Use that password when connecting with `psql` inside the pod:

```bash
psql -U postgres -d postgres
Password for user postgres: <paste password>
```

If you changed the DB name/user in your deployment, adjust accordingly.

---

## 4. Run SQL queries to view documents

Once in `psql`, you can run any SQL query. Useful commands:

### 4.1 List recent user-uploaded files

```sql
SELECT
  id,
  name,
  owner_id,
  status,
  chunk_count,
  created_at
FROM user_file
ORDER BY created_at DESC
LIMIT 20;
```

### 4.2 List canonical documents

```sql
SELECT
  id,
  semantic_identifier,
  source,
  link,
  deleted,
  created_at
FROM document
ORDER BY created_at DESC
LIMIT 20;
```

### 4.3 Join user files to documents

```sql
SELECT
  uf.id AS user_file_id,
  uf.name,
  d.id AS document_id,
  d.semantic_identifier,
  uf.status,
  uf.chunk_count
FROM user_file uf
JOIN document d ON d.id = uf.id::text
ORDER BY uf.created_at DESC
LIMIT 20;
```

### 4.4 Find chunks for a document

```sql
SELECT
  sd.id,
  sd.document_id,
  sd.chunk_ind,
  sd.blurb
FROM search_doc sd
WHERE sd.document_id = '<DOCUMENT_ID>'
ORDER BY sd.chunk_ind;
```

### Exit `psql`

```
\q
```

Exit the pod shell:

```
exit
```

---

## 5. Alternative: Port-forward to PostgreSQL

If you prefer to connect from your local machine (using `psql` installed locally):

1. **Port-forward the service:**
   ```bash
   kubectl port-forward svc/postgresql -n onyx 5432:5432
   ```

2. **Connect with local psql:**
   ```bash
   PGPASSWORD=<password> psql -h localhost -U postgres -d postgres
   ```

3. Run the same SQL queries.

> Remember to stop the port-forward when done (Ctrl+C).

---

## 6. Security notes

- Only exec into the database pod if you have proper privileges.
- Avoid keeping passwords in shell history (use `read -s` or environment variables).
- Consider read-only DB users for inspection tasks.

---

## 7. Summary

1. `kubectl exec -it postgresql-0 -n onyx -- /bin/bash`
2. Retrieve DB password from `postgresql-secret`
3. `psql -U postgres -d postgres`
4. Run SQL (`SELECT * FROM user_file`) to view uploads
5. Exit when done

Following these steps allows you to view all uploaded documents directly from the database in a Kubernetes deployment.***

