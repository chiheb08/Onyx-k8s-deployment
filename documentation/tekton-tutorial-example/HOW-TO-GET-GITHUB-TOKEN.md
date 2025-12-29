# How to Get a GitHub Personal Access Token

This guide shows you step-by-step how to create a GitHub personal access token for the Tekton tutorial.

---

## 🎯 What is a GitHub Personal Access Token?

A **Personal Access Token (PAT)** is like a password that gives applications permission to access your GitHub account. It's safer than using your actual password because:
- ✅ You can revoke it anytime
- ✅ You can limit what it can do (scopes)
- ✅ It's specific to one application

---

## 📋 Step-by-Step Instructions

### **Step 1: Go to GitHub Settings**

1. **Log in to GitHub** (https://github.com)
2. **Click your profile picture** (top right corner)
3. **Click "Settings"** from the dropdown menu

**Or go directly to:** https://github.com/settings/profile

---

### **Step 2: Navigate to Developer Settings**

1. **Scroll down** in the left sidebar
2. **Click "Developer settings"** (at the bottom)

**Or go directly to:** https://github.com/settings/apps

---

### **Step 3: Go to Personal Access Tokens**

1. **Click "Personal access tokens"** in the left sidebar
2. **Click "Tokens (classic)"** (or "Fine-grained tokens" for newer option)

**Or go directly to:** https://github.com/settings/tokens

---

### **Step 4: Generate New Token**

1. **Click "Generate new token"** button
2. **Click "Generate new token (classic)"** (if you see both options)

**Note:** If you see "Fine-grained tokens" option, you can use that too, but "classic" is simpler for this tutorial.

---

### **Step 5: Configure Token**

Fill in the form:

#### **Note (Required)**
- **Name:** Give it a descriptive name
  - Example: `Tekton Pipeline Tutorial`
  - This helps you remember what it's for

#### **Expiration (Optional)**
- Choose how long the token should be valid
- **Recommended:** `90 days` or `No expiration` (for testing)
- For production, use shorter expiration

#### **Select Scopes (Permissions)**

For the Tekton tutorial, you need these scopes:

**Minimum Required:**
- ✅ **`repo`** - Full control of private repositories
  - OR
- ✅ **`public_repo`** - Access public repositories (if your repo is public)

**What each scope does:**
- **`repo`** - Allows the token to:
  - Read and write repository code
  - Clone repositories
  - Access private repositories
- **`public_repo`** - Allows the token to:
  - Read and write public repositories only
  - Cannot access private repositories

**For this tutorial:**
- If your repository is **public**: Use `public_repo`
- If your repository is **private**: Use `repo`

**Other useful scopes (optional):**
- `read:org` - Read org membership (if using organization repos)
- `workflow` - Update GitHub Action workflows (if needed)

---

### **Step 6: Generate Token**

1. **Scroll down** to the bottom
2. **Click "Generate token"** button (green button)

---

### **Step 7: Copy Token Immediately**

⚠️ **IMPORTANT:** GitHub will show your token **ONLY ONCE**

You'll see a page like this:
```
ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**DO THIS IMMEDIATELY:**
1. **Click the copy icon** (📋) next to the token
2. **OR select all and copy** (Cmd+C / Ctrl+C)
3. **Paste it somewhere safe** (text file, password manager, etc.)

**⚠️ WARNING:**
- You **cannot** see this token again after you leave this page
- If you lose it, you'll need to create a new one
- **Never share this token** publicly (it's like a password)

---

### **Step 8: Use Token in Script**

When the `setup.sh` script asks for your GitHub token:

```bash
Enter your GitHub personal access token: 
```

1. **Paste the token** you just copied
2. **Press Enter**

The script will hide what you type (for security).

---

## 🎯 Quick Reference

### **Direct Links:**

- **Settings:** https://github.com/settings/profile
- **Developer Settings:** https://github.com/settings/apps
- **Personal Access Tokens:** https://github.com/settings/tokens

### **Quick Path:**
```
GitHub → Profile Picture → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token
```

---

## 🔐 Security Best Practices

### **✅ DO:**
- ✅ Use descriptive names for tokens
- ✅ Set expiration dates (especially for production)
- ✅ Only grant minimum required permissions
- ✅ Store tokens securely (password manager)
- ✅ Revoke tokens you're not using
- ✅ Use different tokens for different purposes

### **❌ DON'T:**
- ❌ Share tokens publicly
- ❌ Commit tokens to Git repositories
- ❌ Use your main password instead
- ❌ Give tokens more permissions than needed
- ❌ Leave tokens with "No expiration" in production

---

## 🐛 Troubleshooting

### **Problem: "Token has insufficient permissions"**

**Solution:**
1. Go back to token settings
2. Edit the token
3. Add the required scope (`repo` or `public_repo`)
4. Save changes
5. Use the token again

---

### **Problem: "Token expired"**

**Solution:**
1. Go to token settings
2. Generate a new token
3. Update the script/service account with new token

---

### **Problem: "Cannot find Developer settings"**

**Solution:**
- Make sure you're logged in
- Try direct link: https://github.com/settings/apps
- Check if you have the right permissions on your account

---

### **Problem: "Token not working"**

**Check:**
1. Did you copy the entire token? (starts with `ghp_`)
2. Are there any extra spaces?
3. Is the token expired?
4. Does it have the right scopes?

**Solution:**
- Create a new token
- Make sure to select `repo` or `public_repo` scope
- Copy it carefully

---

## 📊 Token Format

GitHub tokens look like this:
```
ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

- Starts with `ghp_`
- Followed by 36 random characters
- Total length: 40 characters

**Example:**
```
ghp_1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s0t
```

---

## 🔄 Revoking Tokens

If you need to revoke a token (security, lost, etc.):

1. Go to: https://github.com/settings/tokens
2. Find your token in the list
3. Click **"Revoke"** button
4. Confirm revocation

**After revoking:**
- Token stops working immediately
- You'll need to create a new token
- Update any services using the old token

---

## 🆚 Classic vs Fine-Grained Tokens

### **Classic Tokens (Recommended for Tutorial)**
- ✅ Simpler to create
- ✅ Works with all GitHub features
- ✅ Good for personal use
- ❌ Broad permissions (all or nothing per scope)

### **Fine-Grained Tokens (Newer Option)**
- ✅ More granular permissions
- ✅ Can limit to specific repositories
- ✅ Better for production
- ❌ More complex to set up
- ❌ Not all features supported yet

**For this tutorial:** Use **Classic tokens** - they're simpler and work perfectly.

---

## ✅ Checklist

Before running the script, make sure you have:

- [ ] GitHub account (free)
- [ ] Logged into GitHub
- [ ] Created personal access token
- [ ] Selected `repo` or `public_repo` scope
- [ ] Copied token to a safe place
- [ ] Ready to paste when script asks

---

## 📚 Additional Resources

- **GitHub Docs:** https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token
- **Token Scopes:** https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps
- **Security Best Practices:** https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens

---

## 🎯 Summary

**To get a GitHub token:**

1. Go to: https://github.com/settings/tokens
2. Click: "Generate new token (classic)"
3. Name it: "Tekton Pipeline Tutorial"
4. Select scope: `repo` (or `public_repo` for public repos)
5. Click: "Generate token"
6. **Copy immediately** (you won't see it again!)
7. Use it in the `setup.sh` script when prompted

**That's it!** The token will allow Tekton to clone your GitHub repository. 🚀

