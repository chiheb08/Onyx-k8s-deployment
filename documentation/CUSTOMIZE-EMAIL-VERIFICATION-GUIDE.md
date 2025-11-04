# Customize Email Verification & Integrate with Invited Users

## 🎯 Overview

This guide explains how to customize email verification in Onyx and integrate it with the internal invited users system. You can customize the email template, verification flow, and combine it with invitation-only registration.

---

## 📋 Current Implementation

### **Email Verification Flow**

1. **User Registration** → User creates account
2. **Token Generation** → System generates verification token
3. **Email Sending** → `send_user_verification_email()` sends email with link
4. **Verification** → User clicks link → Frontend calls `/api/auth/verify` → Backend verifies token
5. **Account Activation** → User account marked as verified

### **Key Files:**

- **Backend Email Function**: `onyx-repo/backend/onyx/auth/email_utils.py` → `send_user_verification_email()`
- **Verification Handler**: `onyx-repo/backend/onyx/auth/users.py` → `on_after_request_verify()`
- **Frontend Verification**: `onyx-repo/web/src/app/auth/verify-email/Verify.tsx`
- **Invited Users**: `onyx-repo/backend/onyx/auth/invited_users.py`

---

## 🔧 Customization Options

### **Option 1: Customize Email Template**

#### **Location**: `onyx-repo/backend/onyx/auth/email_utils.py`

**Current Implementation:**
```python
def send_user_verification_email(
    user_email: str,
    token: str,
    new_organization: bool = False,
    mail_from: str = EMAIL_FROM,
) -> None:
    subject = f"{application_name} Email Verification"
    link = f"{WEB_DOMAIN}/auth/verify-email?token={token}"
    message = (
        f"<p>Click the following link to verify your email address:</p><p>{link}</p>"
    )
    # ... sends email
```

**Customization Example:**
```python
def send_user_verification_email(
    user_email: str,
    token: str,
    new_organization: bool = False,
    mail_from: str = EMAIL_FROM,
    custom_message: str = None,  # Add custom message parameter
) -> None:
    # Custom subject line
    subject = f"Welcome to {application_name} - Verify Your Email"
    
    # Custom verification link
    link = f"{WEB_DOMAIN}/auth/verify-email?token={token}"
    if new_organization:
        link = add_url_params(link, {"first_user": "true"})
    
    # Custom HTML message
    custom_html = custom_message or (
        f"""
        <div style="font-family: Arial, sans-serif;">
            <h2>Welcome to {application_name}!</h2>
            <p>Please verify your email address by clicking the link below:</p>
            <p><a href="{link}" style="background-color: #4CAF50; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;">Verify Email</a></p>
            <p>Or copy and paste this link into your browser:</p>
            <p style="word-break: break-all;">{link}</p>
            <p>This link will expire in 24 hours.</p>
        </div>
        """
    )
    
    html_content = build_html_email(
        application_name,
        "Verify Your Email",
        custom_html,
    )
    
    text_content = f"Verify your email by visiting: {link}"
    send_email(
        user_email,
        subject,
        html_content,
        text_content,
        mail_from,
        inline_png=("logo.png", onyx_file.data),
    )
```

**Steps to Customize:**
1. Edit `onyx-repo/backend/onyx/auth/email_utils.py`
2. Modify the `send_user_verification_email()` function
3. Customize subject, message, HTML template
4. Rebuild and redeploy your backend

---

### **Option 2: Integrate with Invited Users**

#### **Location**: `onyx-repo/backend/onyx/auth/users.py`

**Current Flow:**
- User registers → Verification email sent
- User verifies → Account activated

**Custom Flow with Invited Users:**
- User must be invited → User registers → Verification email sent → User verifies → Account activated

**Implementation:**

**Step 1: Modify Registration to Check Invitation**

```python
# In onyx-repo/backend/onyx/auth/users.py
# Find the create() method in UserManager class

async def create(
    self, user_create: UserCreate, safe: bool = False, request: Optional[Request] = None
) -> User:
    # Check if user is invited (if ENABLE_EMAIL_INVITES is enabled)
    if ENABLE_EMAIL_INVITES:
        verify_email_is_invited(user_create.email)
    
    # Check email domain (if VALID_EMAIL_DOMAINS is set)
    verify_email_domain(user_create.email)
    
    # Continue with normal registration...
    # ... existing code ...
```

**Step 2: Modify Verification Handler to Check Invitation**

```python
# In onyx-repo/backend/onyx/auth/users.py
# Modify on_after_request_verify() method

async def on_after_request_verify(
    self, user: User, token: str, request: Optional[Request] = None
) -> None:
    # Verify email domain
    verify_email_domain(user.email)
    
    # Check if user is still in invited users list (optional)
    if ENABLE_EMAIL_INVITES:
        verify_email_is_invited(user.email)
    
    logger.notice(
        f"Verification requested for user {user.id}. Verification token: {token}"
    )
    
    user_count = await get_user_count()
    send_user_verification_email(
        user.email, token, new_organization=user_count == 1
    )
```

**Step 3: Remove User from Invited List After Verification**

The current implementation already removes users from the invited list when they register. To ensure they're removed only after verification:

```python
# In onyx-repo/backend/onyx/auth/users.py
# Find the verify() method or create a custom handler

async def verify(
    self, user: User, token: str, request: Optional[Request] = None
) -> User:
    # Verify the token (this is handled by fastapi-users)
    # After verification succeeds, remove from invited users
    
    # Remove from invited users list
    if ENABLE_EMAIL_INVITES:
        remove_user_from_invited_users(user.email)
    
    # Mark user as verified
    user.is_verified = True
    
    return user
```

---

### **Option 3: Custom Verification Endpoint**

#### **Create Custom Verification Handler**

**File**: `onyx-repo/backend/onyx/server/auth_custom.py` (new file)

```python
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession
from onyx.db.engine.async_sql_engine import get_async_session
from onyx.auth.users import get_user_manager, UserManager
from onyx.auth.invited_users import remove_user_from_invited_users
from onyx.configs.app_configs import ENABLE_EMAIL_INVITES

router = APIRouter()

@router.post("/auth/verify-custom")
async def custom_verify_email(
    token: str,
    request: Request,
    user_manager: UserManager = Depends(get_user_manager),
    db_session: AsyncSession = Depends(get_async_session),
):
    """
    Custom email verification endpoint with invited users integration.
    """
    try:
        # Verify token using fastapi-users
        user = await user_manager.verify(token, request)
        
        # Custom logic: Remove from invited users after verification
        if ENABLE_EMAIL_INVITES:
            remove_user_from_invited_users(user.email)
            logger.info(f"Removed {user.email} from invited users after verification")
        
        # Add any additional custom logic here
        # e.g., send welcome email, create default projects, etc.
        
        return {"status": "verified", "user_id": str(user.id)}
        
    except Exception as e:
        logger.error(f"Verification failed: {str(e)}")
        raise HTTPException(status_code=400, detail=f"Verification failed: {str(e)}")
```

**Register the Router:**
```python
# In onyx-repo/backend/onyx/main.py
from onyx.server.auth_custom import router as auth_custom_router

app.include_router(auth_custom_router)
```

---

## 🛠️ Configuration Options

### **Environment Variables**

**ConfigMap**: `onyx-k8s-infrastructure/manifests/05-configmap.yaml`

```yaml
# Email Verification
REQUIRE_EMAIL_VERIFICATION: "true"  # Require email verification before login

# Invited Users
ENABLE_EMAIL_INVITES: "true"  # Only invited users can register
VALID_EMAIL_DOMAINS: "yourcompany.com"  # Restrict to company domains

# Email Configuration
EMAIL_FROM: "noreply@yourcompany.com"
WEB_DOMAIN: "https://onyx.yourcompany.com"
```

### **Combined Configuration (Recommended for Internal Use)**

```yaml
# Internal company deployment with invited users + email verification
REQUIRE_EMAIL_VERIFICATION: "true"
ENABLE_EMAIL_INVITES: "true"
VALID_EMAIL_DOMAINS: "yourcompany.com"
```

**This configuration:**
1. ✅ Only allows invited users to register
2. ✅ Restricts to company email domains
3. ✅ Requires email verification before account activation
4. ✅ Perfect for internal company deployments

---

## 📝 Step-by-Step Implementation

### **Scenario: Internal Company with Invited Users + Custom Email Verification**

#### **Step 1: Configure Environment Variables**

```bash
# Edit ConfigMap
kubectl edit configmap onyx-config -n onyx

# Add/Update:
REQUIRE_EMAIL_VERIFICATION: "true"
ENABLE_EMAIL_INVITES: "true"
VALID_EMAIL_DOMAINS: "yourcompany.com"
EMAIL_FROM: "noreply@yourcompany.com"
WEB_DOMAIN: "https://onyx.yourcompany.com"
```

#### **Step 2: Customize Email Template**

1. **Edit**: `onyx-repo/backend/onyx/auth/email_utils.py`
2. **Modify**: `send_user_verification_email()` function
3. **Add**: Company branding, custom message, internal links

**Example Customization:**
```python
def send_user_verification_email(
    user_email: str,
    token: str,
    new_organization: bool = False,
    mail_from: str = EMAIL_FROM,
) -> None:
    # ... existing code ...
    
    # Custom company message
    message = f"""
    <div style="font-family: Arial, sans-serif; max-width: 600px;">
        <h2>Welcome to {application_name}!</h2>
        <p>You've been invited to join our internal knowledge base.</p>
        <p>Please verify your email address to activate your account:</p>
        <p><a href="{link}" style="background-color: #0066cc; color: white; padding: 12px 24px; text-decoration: none; border-radius: 4px; display: inline-block;">Verify Email Address</a></p>
        <p><strong>This link expires in 24 hours.</strong></p>
        <p>If you didn't request this, please contact IT support.</p>
        <hr>
        <p style="color: #666; font-size: 12px;">This is an internal company system. Do not share this link.</p>
    </div>
    """
    
    # ... rest of function ...
```

#### **Step 3: Integrate Invited Users Check**

1. **Edit**: `onyx-repo/backend/onyx/auth/users.py`
2. **Ensure**: `verify_email_is_invited()` is called during registration
3. **Ensure**: User is removed from invited list after verification

**Current Code Already Does This:**
```python
# In UserManager.create() method (line ~312)
if ENABLE_EMAIL_INVITES:
    verify_email_is_invited(user_create.email)  # ✅ Already checks invitation

# In UserManager.create() method (line ~363)
if ENABLE_EMAIL_INVITES:
    remove_user_from_invited_users(user_create.email)  # ✅ Removes after registration
```

**To Remove Only After Verification:**
```python
# Modify on_after_request_verify() to NOT remove immediately
# Instead, remove in custom verification handler (see Option 3 above)
```

#### **Step 4: Test the Flow**

1. **Invite a user**:
```bash
# Via API or Admin UI
POST /api/manage/admin/bulk-invite-users
Body: {"emails": ["user@yourcompany.com"]}
```

2. **User registers** with invited email
3. **User receives** verification email
4. **User clicks** verification link
5. **User account** is activated

---

## 🔐 Security Considerations

### **Token Expiration**
- Verification tokens expire after a set time (default: 24 hours)
- Tokens are single-use (cannot be reused)
- Tokens are cryptographically secure

### **Invitation Security**
- Invited users list is stored in Redis/Key-Value store
- Only admins can add/remove invited users
- Email domain validation provides additional security layer

### **Combined Security**
- ✅ User must be invited (whitelist check)
- ✅ User must have company email domain
- ✅ User must verify email before account activation
- ✅ Triple-layer security for internal deployments

---

## 🎨 Customization Examples

### **Example 1: Custom Welcome Message**

```python
def send_user_verification_email(
    user_email: str,
    token: str,
    new_organization: bool = False,
    mail_from: str = EMAIL_FROM,
) -> None:
    # ... existing code ...
    
    welcome_message = "Welcome to our internal knowledge base!" if not new_organization else "You're the first user! Welcome!"
    
    message = f"""
    <div style="font-family: Arial, sans-serif;">
        <h2>{welcome_message}</h2>
        <p>Your account has been created. Please verify your email to get started.</p>
        <p><a href="{link}">Verify Email</a></p>
    </div>
    """
```

### **Example 2: Add Company Logo**

```python
# In send_user_verification_email()
# The function already includes logo via inline_png=("logo.png", onyx_file.data)
# To customize, modify the logo file or add additional branding
```

### **Example 3: Custom Verification URL**

```python
# Change the verification URL structure
link = f"{WEB_DOMAIN}/auth/verify-email?token={token}&source=invitation"
# Or use internal domain
link = f"https://internal.yourcompany.com/verify?token={token}"
```

---

## 📊 Integration Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│              INVITED USERS + EMAIL VERIFICATION              │
└─────────────────────────────────────────────────────────────┘

1. Admin invites user
   ↓
   [User added to invited_users list in Redis/KV store]

2. User receives invitation (if ENABLE_EMAIL_INVITES=true)
   ↓
   [Invitation email sent]

3. User registers with invited email
   ↓
   [verify_email_is_invited() checks whitelist]
   [verify_email_domain() checks domain]
   [User account created, is_verified=false]

4. Verification email sent
   ↓
   [send_user_verification_email() called]
   [Email with verification link sent]

5. User clicks verification link
   ↓
   [Frontend: /auth/verify-email?token=xxx]
   [Backend: POST /api/auth/verify]
   [Token validated, user.is_verified=true]

6. User removed from invited list (optional)
   ↓
   [remove_user_from_invited_users() called]
   [User can now login]
```

---

## 🚀 Quick Start Guide

### **For Internal Company Deployment:**

1. **Set ConfigMap values:**
```yaml
REQUIRE_EMAIL_VERIFICATION: "true"
ENABLE_EMAIL_INVITES: "true"
VALID_EMAIL_DOMAINS: "yourcompany.com"
```

2. **Invite users:**
```bash
# Via Admin UI or API
POST /api/manage/admin/bulk-invite-users
```

3. **Customize email template** (optional):
   - Edit `onyx-repo/backend/onyx/auth/email_utils.py`
   - Modify `send_user_verification_email()` function

4. **Deploy and test:**
   - Rebuild backend if you modified code
   - Test registration flow
   - Test verification flow

---

## 📋 Troubleshooting

### **Issue: Verification emails not sending**

**Check:**
1. Email configuration in ConfigMap (`EMAIL_FROM`, SMTP settings)
2. Email service is running and accessible
3. Check backend logs for email errors

### **Issue: Invited users can't register**

**Check:**
1. `ENABLE_EMAIL_INVITES` is set correctly
2. User email is in invited users list
3. Email domain matches `VALID_EMAIL_DOMAINS` (if set)

### **Issue: Verification link not working**

**Check:**
1. `WEB_DOMAIN` is set correctly in ConfigMap
2. Frontend verification page is accessible
3. Token hasn't expired (24h default)

---

## 📚 Related Documentation

- **Company-Only Authentication**: `COMPANY-ONLY-AUTHENTICATION.md`
- **Disable Invited Users**: `DISABLE-INVITED-USERS-ONLY.md`
- **How Sessions Work**: `HOW-SESSIONS-WORK.md`

---

**Document Version:** 1.0  
**Last Updated:** [Current Date]  
**Author:** AI Assistant

