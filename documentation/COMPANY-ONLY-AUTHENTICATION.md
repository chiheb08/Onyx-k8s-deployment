# Company-Only Authentication Setup for Onyx

## 🎯 Overview

This guide explains how to configure Onyx for company-only authentication, ensuring that only invited employees can create accounts and access the system. This is essential for internal company deployments where security and access control are critical.

---

## 🔐 Authentication Methods

### 1. **Invitation-Only Registration (Recommended)**

**How it works:**
- Only users who have been explicitly invited can create accounts
- Admins must invite users via email before they can register
- Prevents unauthorized access from external users

**Configuration:**
```yaml
ENABLE_EMAIL_INVITES: "true"
```

### 2. **Domain-Based Registration**

**How it works:**
- Only users with company email domains can register
- Automatically restricts access to company employees
- Provides additional security layer

**Configuration:**
```yaml
VALID_EMAIL_DOMAINS: "yourcompany.com,subsidiary.com"
```

### 3. **Combined Approach (Most Secure)**

**How it works:**
- Users must have a company email domain AND be invited
- Double security layer for maximum protection
- Recommended for sensitive company data

**Configuration:**
```yaml
ENABLE_EMAIL_INVITES: "true"
VALID_EMAIL_DOMAINS: "yourcompany.com"
```

---

## 🛠️ Configuration Steps

### Step 1: Update ConfigMap

Update your `05-configmap.yaml` with company authentication settings:

```yaml
# ============================================================================
# COMPANY-ONLY AUTHENTICATION SETTINGS
# ============================================================================
# ENABLE_EMAIL_INVITES: Enable invitation-only registration
# - "true": Only invited users can create accounts (RECOMMENDED for company use)
# - "false": Anyone can register (NOT recommended for company use)
# 
# VALID_EMAIL_DOMAINS: Restrict registration to company email domains
# - Comma-separated list of allowed domains
# - Example: "yourcompany.com,subsidiary.com"
# - Only users with emails from these domains can register
# - Leave empty to allow any domain (NOT recommended for company use)
# 
# Used by: API Server, Web Server
# ============================================================================
ENABLE_EMAIL_INVITES: "true"
VALID_EMAIL_DOMAINS: "yourcompany.com"
```

### Step 2: Replace Company Domain

**IMPORTANT:** Replace `yourcompany.com` with your actual company domain:

```yaml
VALID_EMAIL_DOMAINS: "acme-corp.com"  # Replace with your company domain
```

### Step 3: Deploy Configuration

```bash
# Apply the updated configuration
oc apply -f manifests/05-configmap.yaml

# Restart the API server to pick up new settings
oc rollout restart deployment/api-server
```

---

## 👥 User Management

### Inviting Users

#### Method 1: Using the Onyx Admin Interface

1. **Access Admin Panel:**
   - Log in to Onyx as an admin user
   - Navigate to the admin section
   - Go to "User Management" or "Invite Users"

2. **Send Invitations:**
   - Enter the email address of the user to invite
   - Click "Send Invitation"
   - The user will receive an email with a registration link

#### Method 2: Using the API (Programmatic)

```bash
# Get API key from admin user
API_KEY="your-api-key-here"

# Invite a user via API
curl -X POST "https://your-onyx-domain.com/api/user/invite" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "newuser@yourcompany.com",
    "role": "basic"
  }'
```

#### Method 3: Using the Invitation Script

Use the provided invitation management script:

```bash
# Invite a single user
./scripts/invite-user.sh "john.doe@yourcompany.com"

# Invite multiple users
./scripts/invite-users.sh users.txt
```

### User Roles

Onyx supports different user roles for access control:

- **ADMIN**: Full system access, can manage users and settings
- **CURATOR**: Can manage content and connectors for their groups
- **GLOBAL_CURATOR**: Can manage content for all groups they're in
- **BASIC**: Standard user access
- **LIMITED**: Restricted access to basic features

---

## 🔧 Advanced Configuration

### Email Configuration

For invitation emails to work, configure SMTP settings:

```yaml
# Email settings for sending invitations
SMTP_SERVER: "smtp.yourcompany.com"
SMTP_PORT: "587"
SMTP_USER: "onyx@yourcompany.com"
SMTP_PASS: "your-email-password"
EMAIL_FROM: "onyx@yourcompany.com"
```

### OAuth Integration (Optional)

For companies using Google Workspace or Microsoft 365:

```yaml
# Google OAuth (for Google Workspace)
AUTH_TYPE: "google_oauth"
OAUTH_CLIENT_ID: "your-google-client-id"
OAUTH_CLIENT_SECRET: "your-google-client-secret"

# Or Microsoft OAuth (for Microsoft 365)
AUTH_TYPE: "oidc"
OPENID_CONFIG_URL: "https://login.microsoftonline.com/your-tenant-id/v2.0/.well-known/openid_configuration"
```

### SAML Integration (Enterprise)

For enterprise SAML integration:

```yaml
AUTH_TYPE: "saml"
# Additional SAML configuration required
```

---

## 🚀 Deployment Checklist

### Pre-Deployment

- [ ] Update `VALID_EMAIL_DOMAINS` with your company domain
- [ ] Configure email settings for invitations
- [ ] Plan user roles and permissions
- [ ] Prepare initial admin user invitation

### Post-Deployment

- [ ] Test user invitation process
- [ ] Verify domain restrictions work
- [ ] Create initial admin user
- [ ] Document user management procedures
- [ ] Train administrators on user management

---

## 🔍 Troubleshooting

### Common Issues

#### 1. **Users Can't Register**

**Problem:** Users get "User not on allowed user whitelist" error

**Solution:**
- Ensure `ENABLE_EMAIL_INVITES: "true"` is set
- Verify the user has been invited via admin interface
- Check that the user's email domain is in `VALID_EMAIL_DOMAINS`

#### 2. **Invitation Emails Not Sent**

**Problem:** Invitation emails are not being delivered

**Solution:**
- Verify SMTP settings are correct
- Check email server logs
- Ensure `EMAIL_CONFIGURED` is true
- Test email configuration

#### 3. **Domain Restrictions Not Working**

**Problem:** Users from non-company domains can still register

**Solution:**
- Verify `VALID_EMAIL_DOMAINS` is set correctly
- Check that the domain is in the allowed list
- Ensure the configuration has been applied

### Verification Commands

```bash
# Check current configuration
oc get configmap onyx-config -o yaml | grep -E "(ENABLE_EMAIL_INVITES|VALID_EMAIL_DOMAINS)"

# Check API server logs
oc logs deployment/api-server | grep -i "invite\|domain\|auth"

# Test user invitation
curl -X POST "https://your-onyx-domain.com/api/user/invite" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email": "test@yourcompany.com", "role": "basic"}'
```

---

## 📊 Security Best Practices

### 1. **Regular User Audits**

- Review user list monthly
- Remove inactive users
- Verify user roles are appropriate
- Check for unauthorized access attempts

### 2. **Password Policies**

Configure strong password requirements:

```yaml
PASSWORD_MIN_LENGTH: "12"
PASSWORD_REQUIRE_UPPERCASE: "true"
PASSWORD_REQUIRE_LOWERCASE: "true"
PASSWORD_REQUIRE_DIGIT: "true"
PASSWORD_REQUIRE_SPECIAL_CHAR: "true"
```

### 3. **Session Management**

```yaml
# Shorter session timeouts for security
SESSION_EXPIRE_TIME_SECONDS: "28800"  # 8 hours instead of 24
```

### 4. **Monitoring and Logging**

- Enable audit logging
- Monitor failed login attempts
- Set up alerts for suspicious activity
- Regular security reviews

---

## 📚 Additional Resources

### Related Documentation

- [Environment Variables Explained](ENVIRONMENT-VARIABLES-EXPLAINED.md)
- [Network Policies Basics](NETWORK-POLICIES-BASICS.md)
- [Celery Workers Architecture](CELERY-WORKERS-ARCHITECTURE-DIAGRAM.md)

### API Endpoints

- `POST /api/user/invite` - Invite a new user
- `GET /api/user/list` - List all users
- `PUT /api/user/{user_id}/role` - Update user role
- `DELETE /api/user/{user_id}` - Remove user

### Configuration Reference

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `ENABLE_EMAIL_INVITES` | Enable invitation-only registration | `false` | Yes |
| `VALID_EMAIL_DOMAINS` | Allowed email domains | `""` | Yes |
| `AUTH_TYPE` | Authentication method | `basic` | Yes |
| `SMTP_SERVER` | Email server for invitations | `""` | Yes |
| `SMTP_USER` | Email username | `""` | Yes |
| `SMTP_PASS` | Email password | `""` | Yes |

---

## 🎯 Summary

Company-only authentication in Onyx provides:

1. **Security**: Only invited company employees can access the system
2. **Control**: Admins control who can join and what they can access
3. **Compliance**: Meets enterprise security requirements
4. **Flexibility**: Supports multiple authentication methods
5. **Auditability**: Track user access and permissions

By following this guide, you can ensure that your Onyx deployment is secure and accessible only to authorized company personnel.

---

## 📞 Support

For additional help with company authentication setup:

1. Check the troubleshooting section above
2. Review Onyx documentation
3. Contact your system administrator
4. Reach out to the Onyx community

Remember to replace `yourcompany.com` with your actual company domain and configure email settings for the invitation system to work properly.
