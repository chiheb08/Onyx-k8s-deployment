# Show/Hide Password Toggle – Quick Guide

This guide explains, step by step, how we added an eye icon to reveal or hide the password on Onyx’s login form (and any other Formik field that reuses `TextFormField`).

---

## Overview

| Area | File | Purpose |
|------|------|---------|
| Shared form field | `web/src/components/Field.tsx` | Allow inputs to render a right-aligned control (`endAdornment`). |
| Login form | `web/src/app/auth/login/EmailPasswordForm.tsx` | Show/hide password logic using the new prop. |

---

## Step 1 – Enhance `TextFormField`
**File:** `web/src/components/Field.tsx`

1. **Import `ReactNode`** so the field can accept arbitrary JSX adornments:
   ```diff
   - import { useState, useCallback, useEffect, memo, useRef } from "react";
   + import {
   +   useState,
   +   useCallback,
   +   useEffect,
   +   memo,
   +   useRef,
   +   ReactNode,
   + } from "react";
   ```

2. **Expose an `endAdornment` prop:**
   ```diff
     className,
   +  endAdornment,
   }: {
   ...
     className?: string;
   +  endAdornment?: ReactNode;
   })
   ```

3. **Render the adornment inside the input wrapper and reserve space:**
   ```diff
         className={`
             ...
   -          ${className}
   +          ${endAdornment ? "pr-10" : ""}
   +          ${className}
             bg-background-neutral-00
         `}
         ...
       />
   +    {endAdornment && (
   +      <div className="absolute inset-y-0 right-3 flex items-center">
   +        {endAdornment}
   +      </div>
   +    )}
   ```

✅ Result: any consumer of `TextFormField` can now supply a button or icon via `endAdornment`, and the input automatically adds padding on the right.

---

## Step 2 – Use the Toggle on the Login Form
**File:** `web/src/app/auth/login/EmailPasswordForm.tsx`

1. **Import icons:**
   ```ts
   import { FiEye, FiEyeOff } from "react-icons/fi";
   ```

2. **Track whether the password is visible:**
   ```ts
   const [showPassword, setShowPassword] = useState(false);
   const togglePasswordVisibility = () => setShowPassword((prev) => !prev);
   ```

3. **Update the password field:**
   ```tsx
   <TextFormField
     name="password"
     label="Password"
     type={showPassword ? "text" : "password"}
     placeholder="**************"
     data-testid="password"
     endAdornment={
       <button
         type="button"
         onClick={togglePasswordVisibility}
         aria-label={showPassword ? "Hide password" : "Show password"}
         className="text-text-03 hover:text-text-04 focus:outline-none"
       >
         {showPassword ? <FiEyeOff size={16} /> : <FiEye size={16} />}
       </button>
     }
   />
   ```

Now users can tap the eye icon to switch between masked and plain text.

---

## Deployment Checklist

1. Apply the code changes in `onyx-repo`.
2. Build the web app (`pnpm build` or your CI pipeline).
3. Redeploy the frontend.

That’s all—no backend changes required. The pattern is reusable for other forms that need a toggle or trailing button inside the input field.
