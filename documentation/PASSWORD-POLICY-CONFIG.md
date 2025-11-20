# Onyx Password Policy Configuration (Signup & Reset)

This guide explains how to enforce strong password requirements in Onyx, including:

- Minimum length of 15 characters
- At least 1 uppercase letter
- At least 1 lowercase letter
- At least 1 digit
- At least 1 special character
- Ability to toggle requirements via environment variables

---

## 1. Overview

Onyx already ships with a configurable password policy. The backend validates passwords in `backend/onyx/auth/users.py` (see `UserManager.validate_password`) using the following environment variables:

| Environment Variable | Type | Default | Purpose |
|----------------------|------|---------|---------|
| `PASSWORD_MIN_LENGTH` | Integer | `8` | Minimum characters |
| `PASSWORD_MAX_LENGTH` | Integer | `64` | Maximum characters |
| `PASSWORD_REQUIRE_UPPERCASE` | Boolean (`true`/`false`) | `false` | Require uppercase letter |
| `PASSWORD_REQUIRE_LOWERCASE` | Boolean | `false` | Require lowercase letter |
| `PASSWORD_REQUIRE_DIGIT` | Boolean | `false` | Require number |
| `PASSWORD_REQUIRE_SPECIAL_CHAR` | Boolean | `false` | Require special character |
| `PASSWORD_SPECIAL_CHARS` *(optional)* | String | `!@#$%^&*()` etc.¹ | Allowed special characters |

> ¹ `PASSWORD_SPECIAL_CHARS` is only needed if you want to restrict which special characters are accepted. By default, the backend uses `string.punctuation`.

When any of these variables are set, the backend enforces the policy during:

- User signup (`/api/auth/signup`)
- Password reset (`/api/password/change-my-password`)
- Admin-driven password reset

If a password fails validation, the user gets an HTTP 400 response with a descriptive message (e.g., “Password must contain at least one uppercase letter.”).

---

## 2. Required Settings for Strong Policy

To enforce the requested policy (15+ characters, uppercase, lowercase, digit, special char), set the following environment variables:

```bash
PASSWORD_MIN_LENGTH=15
PASSWORD_REQUIRE_UPPERCASE=true
PASSWORD_REQUIRE_LOWERCASE=true
PASSWORD_REQUIRE_DIGIT=true
PASSWORD_REQUIRE_SPECIAL_CHAR=true
```

Optional (if you want to define exactly which special characters are allowed):

```bash
PASSWORD_SPECIAL_CHARS="!@#$%^&*()-_=+[]{};:,.<>/?"
```

> Keep `PASSWORD_MAX_LENGTH` at default (64) unless you want to restrict further.

---

## 3. OpenShift / Kubernetes Deployment Example

### 3.1 Update ConfigMap (`05-configmap.yaml`)

If you manage Onyx via the provided OpenShift/K8s manifests, edit `onyx-k8s-infrastructure/manifests/05-configmap.yaml`:

```yaml
data:
  # Existing entries...
  PASSWORD_MIN_LENGTH: "15"
  PASSWORD_REQUIRE_UPPERCASE: "true"
  PASSWORD_REQUIRE_LOWERCASE: "true"
  PASSWORD_REQUIRE_DIGIT: "true"
  PASSWORD_REQUIRE_SPECIAL_CHAR: "true"
  # Optional:
  # PASSWORD_SPECIAL_CHARS: "!@#$%^&*()-_=+[]{};:,.<>/?"
```

Apply the ConfigMap:

```bash
kubectl apply -f manifests/05-configmap.yaml
# or
oc apply -f manifests/05-configmap.yaml
```

### 3.2 Roll Pods

After updating the ConfigMap, restart pods that rely on these variables (API server & web server):

```bash
kubectl rollout restart deployment/api-server deployment/web-server -n <namespace>
# or using oc
oc rollout restart deployment/api-server deployment/web-server -n <namespace>
```

---

## 4. Verifying the Policy

1. **Signup Flow:**
   - Open the signup page (`/auth/signup`).
   - Try using a password that violates each rule (e.g., only lowercase).
   - The UI should display the backend error message.

2. **Password Reset:**
   - Login, go to “User Settings” → “Security” → “Change Password”.
   - Attempt to change password with invalid values.
   - Expect same error messages.

3. **API Test (optional):**
   ```bash
   curl -X POST https://<domain>/api/auth/signup \
     -H "Content-Type: application/json" \
     -d '{
       "email": "user@example.com",
       "password": "shortpass",
       "first_name": "Test",
       "last_name": "User"
     }'
   ```
   - Response should include `"Password must be at least 15 characters long."`

---

## 5. Toggling the Policy

Because each requirement is controlled by an individual environment variable, you can easily toggle them without code changes:

- Set variable to `"true"` to enforce.
- Set variable to `"false"` (or remove it) to disable.

Examples:

| Requirement | Toggle |
|-------------|--------|
| Uppercase required | `PASSWORD_REQUIRE_UPPERCASE=true` |
| Uppercase optional | `PASSWORD_REQUIRE_UPPERCASE=false` |
| Min length 12 | `PASSWORD_MIN_LENGTH=12` |
| Disable special char requirement | `PASSWORD_REQUIRE_SPECIAL_CHAR=false` |

> Restart the API server after changing the ConfigMap to apply the new policy.

---

## 6. Where to Update in Another Environment

If you deploy Onyx without the provided manifests (e.g., Docker Compose, bare metal), set the environment variables directly in your service definition:

- **Docker Compose (`docker-compose.yml`):**
  ```yaml
  services:
    api-server:
      environment:
        PASSWORD_MIN_LENGTH: "15"
        PASSWORD_REQUIRE_UPPERCASE: "true"
        PASSWORD_REQUIRE_LOWERCASE: "true"
        PASSWORD_REQUIRE_DIGIT: "true"
        PASSWORD_REQUIRE_SPECIAL_CHAR: "true"
  ```

- **Systemd / bare metal:**
  ```
  export PASSWORD_MIN_LENGTH=15
  export PASSWORD_REQUIRE_UPPERCASE=true
  ...
  ```
  Then restart the API server process.

---

## 7. FAQ

**Q:** Does the frontend enforce these rules?  
**A:** The frontend displays backend error messages but the actual validation happens server-side. This ensures API-only clients also comply.

**Q:** Do these rules affect OAuth users?  
**A:** No. OAuth flows typically rely on external identity providers. These settings only affect local password-based users.

**Q:** Can I enforce different policies per tenant?  
**A:** Currently, the password policy is global per deployment because it relies on environment variables.

**Q:** What about auto-generated passwords?  
**A:** The `generate_password()` helper in `backend/onyx/auth/users.py` can be adjusted if you want generated passwords to comply with the same rules.

---

## 8. Summary

1. **Enable strong policy:** Set `PASSWORD_MIN_LENGTH=15` and require uppercase, lowercase, digit, special char via env vars.
2. **Update config:** Modify ConfigMap (or env vars) and restart API server/web server.
3. **Verify:** Test signup/reset flows to ensure the policy is enforced.
4. **Maintain:** Toggle requirements via env vars as needed.

With these steps, you can enforce strict password security in Onyx while keeping the configuration flexible through environment variables.

