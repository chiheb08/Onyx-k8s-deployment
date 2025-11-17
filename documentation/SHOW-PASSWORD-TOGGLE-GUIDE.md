# Show/Hide Password Toggle – Implementation Guide

This guide provides step-by-step instructions with exact code comparisons (old vs. new) for adding a show/hide password toggle to the Onyx login form.

**✅ NOTE:** This feature is **already implemented** in the Onyx codebase. You can verify the implementation by checking:
- `web/src/components/Field.tsx` (lines 38, 250, 278, 374, 382-386)
- `web/src/app/auth/login/EmailPasswordForm.tsx` (lines 15, 37-41, 155, 158-167)

This guide shows you exactly what was implemented, so you can either:
1. **Verify** your code matches the official implementation
2. **Re-implement** it if needed in a different environment
3. **Understand** how the feature works

---

## Overview

| Area | File | Purpose |
|------|------|---------|
| Shared form field | `web/src/components/Field.tsx` | Allow inputs to render a right-aligned control (`endAdornment`). |
| Login form | `web/src/app/auth/login/EmailPasswordForm.tsx` | Show/hide password logic using the new prop. |

---

## Step 1 – Enhance `TextFormField` Component

**File:** `web/src/components/Field.tsx`

### 1.1 Add `ReactNode` to React Imports

**📍 WHERE TO FIND IT:**
1. Open the file `web/src/components/Field.tsx`
2. Scroll to the **top of the file** (around line 32-39)
3. Look for a section that says `import { ... } from "react";`
4. You should see something like this:

```typescript
import {
  useState,
  useCallback,
  useEffect,
  memo,
  useRef,
} from "react";
```

**✏️ WHAT TO CHANGE:**

--- old ---
```typescript
import {
  useState,
  useCallback,
  useEffect,
  memo,
  useRef,
} from "react";
```

--- new ---
```typescript
import {
  useState,
  useCallback,
  useEffect,
  memo,
  useRef,
  ReactNode,  // ← ADD THIS LINE (add a comma after useRef, then add ReactNode)
} from "react";
```

**📝 STEP-BY-STEP:**
1. Find the line that says `useRef,` (it should be the last item before the closing `}`)
2. Add a comma after `useRef,` if it doesn't have one
3. On the next line, add `ReactNode,` (with a comma at the end)
4. Make sure the closing `}` and `from "react";` stay on the same lines

---

### 1.2 Add `endAdornment` Prop to Function Parameters

**📍 WHERE TO FIND IT:**
1. In the same file (`Field.tsx`), scroll down to find the function that starts with `export function TextFormField({`
2. This should be around **line 223-250**
3. Look for the function parameters list - you'll see many properties like `name`, `label`, `placeholder`, etc.
4. Find the last property in the list (it should be `className,`)
5. Right after `className,`, you'll see a closing `}: {` - this is where the type definition starts

**✏️ WHAT TO CHANGE:**

**PART A - Add `endAdornment` to the function parameters:**

Look for this section (around line 249-250):
```typescript
  className,
}: {
```

--- old ---
```typescript
  vertical,
  className,
}: {
```

--- new ---
```typescript
  vertical,
  className,
  endAdornment,  // ← ADD THIS LINE (add a comma after className, then add endAdornment,)
}: {
```

**PART B - Add `endAdornment?: ReactNode;` to the type definition:**

Now look a bit further down (around line 277-278) where you see the type definitions. Find the line that says `className?: string;` - this should be near the end of the type definition object.

--- old ---
```typescript
  width?: string;
  vertical?: boolean;
  className?: string;
})
```

--- new ---
```typescript
  width?: string;
  vertical?: boolean;
  className?: string;
  endAdornment?: ReactNode;  // ← ADD THIS LINE (add after className?: string;)
})
```

**📝 STEP-BY-STEP:**
1. Find the function parameters list (the part inside `export function TextFormField({ ... })`)
2. Find `className,` (should be near the end of the parameter list)
3. Add a new line after `className,` and type: `endAdornment,`
4. Now find the type definition section (the part after `}: {`)
5. Find `className?: string;` (should be near the end)
6. Add a new line after `className?: string;` and type: `endAdornment?: ReactNode;`

---

### 1.3 Add Padding for Adornment and Render It

**📍 WHERE TO FIND IT:**
1. Still in the same file (`Field.tsx`), scroll down inside the `TextFormField` function
2. Look for an `<input>` element (around line 360-381)
3. You'll see it has a `className` prop with many lines of CSS classes
4. Find the line that says `px-3` (this is the horizontal padding)
5. Right after `px-3`, you need to add the conditional padding
6. Then, after the closing `/>` of the input element, you need to add the adornment rendering code

**✏️ WHAT TO CHANGE:**

**PART A - Add padding in the className:**

Find the `className` section of the `<input>` element. The className is a very long multi-line string. You need to find the section near the end, right before `${className}`. Look for this pattern:

```typescript
    ${isCode ? "font-mono" : ""}
    ${className}
    bg-background-neutral-00
```

--- old ---
```typescript
    ${isCode ? "font-mono" : ""}
    ${className}
    bg-background-neutral-00
```

--- new ---
```typescript
    ${isCode ? "font-mono" : ""}
    ${endAdornment ? "pr-10" : ""}  // ← ADD THIS LINE (add right before ${className})
    ${className}
    bg-background-neutral-00
```

**Note:** In the actual code, this line appears around line 374, after many other CSS classes. The important thing is to add it right before `${className}` in the className string.

**PART B - Add the adornment rendering code after the input:**

Now scroll down a bit more. You should see the input element closing with `/>`. Right after that `/>`, you need to add the new code.

Look for this:
```typescript
  autoComplete={autoCompleteDisabled ? "off" : undefined}
/>
```

--- old ---
```typescript
  autoComplete={autoCompleteDisabled ? "off" : undefined}
/>
```

--- new ---
```typescript
  autoComplete={autoCompleteDisabled ? "off" : undefined}
/>
{endAdornment && (  // ← ADD THIS ENTIRE BLOCK (starts right after the />)
  <div className="absolute inset-y-0 right-3 flex items-center">
    {endAdornment}
  </div>
)}
```

**📝 STEP-BY-STEP:**
1. Find the `<input>` element inside the `TextFormField` function (it's actually a `<Field>` component with `as="input"`)
2. Find the `className` prop (it's a very long multi-line string with backticks, starting around line 339)
3. Scroll down through all the CSS classes until you find `${isCode ? "font-mono" : ""}` (around line 373)
4. Right after that line, add a new line and type: `${endAdornment ? "pr-10" : ""}`
5. Make sure it's placed right before `${className}` (which should be on the next line)
6. Now find where the input element ends (look for `/>` around line 381)
7. Right after the `/>`, press Enter to create a new line
8. Copy and paste this entire block:
   ```typescript
   {endAdornment && (
     <div className="absolute inset-y-0 right-3 flex items-center">
       {endAdornment}
     </div>
   )}
   ```

**✅ VERIFICATION:** The parent `<div>` wrapper already has `relative` class in the actual implementation (line 330: `className={`w-full flex ${includeRevert && "gap-x-2"} relative`}`), so the absolute positioning will work correctly.

---

## Step 2 – Add Toggle to Login Form

**File:** `web/src/app/auth/login/EmailPasswordForm.tsx`

### 2.1 Import Eye Icons

**📍 WHERE TO FIND IT:**
1. Open the file `web/src/app/auth/login/EmailPasswordForm.tsx`
2. Scroll to the **very top of the file** (lines 1-15)
3. You'll see many `import` statements
4. Find the last `import` statement (it should be around line 14-15, something like `import { validateInternalRedirect } from ...`)

**✏️ WHAT TO CHANGE:**

--- old ---
```typescript
import { TextFormField } from "@/components/Field";
import { usePopup } from "@/components/admin/connectors/Popup";
import { basicLogin, basicSignup } from "@/lib/user";
import Button from "@/refresh-components/buttons/Button";
import { Form, Formik } from "formik";
import * as Yup from "yup";
import { requestEmailVerification } from "../lib";
import { useState } from "react";
import { Spinner } from "@/components/Spinner";
import Link from "next/link";
import { useUser } from "@/components/user/UserProvider";
import { validateInternalRedirect } from "@/lib/auth/redirectValidation";
```

--- new ---
```typescript
import { TextFormField } from "@/components/Field";
import { usePopup } from "@/components/admin/connectors/Popup";
import { basicLogin, basicSignup } from "@/lib/user";
import Button from "@/refresh-components/buttons/Button";
import { Form, Formik } from "formik";
import * as Yup from "yup";
import { requestEmailVerification } from "../lib";
import { useState } from "react";
import { Spinner } from "@/components/Spinner";
import Link from "next/link";
import { useUser } from "@/components/user/UserProvider";
import { validateInternalRedirect } from "@/lib/auth/redirectValidation";
import { FiEye, FiEyeOff } from "react-icons/fi";  // ← ADD THIS LINE (add at the end of all imports)
```

**📝 STEP-BY-STEP:**
1. Find the last `import` statement in the file (should be `import { validateInternalRedirect }...`)
2. Press Enter after that line to create a new line
3. Type: `import { FiEye, FiEyeOff } from "react-icons/fi";`
4. Make sure it's at the same indentation level as the other imports

---

### 2.2 Add Password Visibility State

**📍 WHERE TO FIND IT:**
1. Still in the same file (`EmailPasswordForm.tsx`), scroll down past the imports
2. Find the function that starts with `export default function EmailPasswordForm({`
3. Inside that function, you'll see several lines that start with `const` or `useState`
4. Look for this line: `const [isWorking, setIsWorking] = useState<boolean>(false);`
5. This should be around **line 36-37**
6. Right after this line, you need to add the new state and function

**✏️ WHAT TO CHANGE:**

--- old ---
```typescript
export default function EmailPasswordForm({
  isSignup = false,
  shouldVerify,
  referralSource,
  nextUrl,
  defaultEmail,
  isJoin = false,
}: EmailPasswordFormProps) {
  const { user } = useUser();
  const { popup, setPopup } = usePopup();
  const [isWorking, setIsWorking] = useState<boolean>(false);
```

--- new ---
```typescript
export default function EmailPasswordForm({
  isSignup = false,
  shouldVerify,
  referralSource,
  nextUrl,
  defaultEmail,
  isJoin = false,
}: EmailPasswordFormProps) {
  const { user } = useUser();
  const { popup, setPopup } = usePopup();
  const [isWorking, setIsWorking] = useState<boolean>(false);
  const [showPassword, setShowPassword] = useState<boolean>(false);  // ← ADD THIS LINE

  const togglePasswordVisibility = () => {  // ← ADD THIS FUNCTION (add after the useState line)
    setShowPassword((prev) => !prev);
  };
```

**📝 STEP-BY-STEP:**
1. Find the line: `const [isWorking, setIsWorking] = useState<boolean>(false);`
2. Press Enter after that line to create a new line
3. Type: `const [showPassword, setShowPassword] = useState<boolean>(false);`
4. Press Enter again to create another new line
5. Copy and paste this entire function:
   ```typescript
   const togglePasswordVisibility = () => {
     setShowPassword((prev) => !prev);
   };
   ```

---

### 2.3 Update Password Field with Toggle

**📍 WHERE TO FIND IT:**
1. Still in the same file (`EmailPasswordForm.tsx`), scroll down further
2. Look for a `<Form>` component (this is from Formik)
3. Inside the `<Form>`, you'll see two `TextFormField` components:
   - First one is for `email`
   - Second one is for `password` (this is the one you need to change)
4. The password field should look like this:
   ```typescript
   <TextFormField
     name="password"
     label="Password"
     type="password"
     placeholder="**************"
     data-testid="password"
   />
   ```
5. This should be around **line 152-168**

**✏️ WHAT TO CHANGE:**

--- old ---
```typescript
<TextFormField
  name="password"
  label="Password"
  type="password"
  placeholder="**************"
  data-testid="password"
/>
```

--- new ---
```typescript
<TextFormField
  name="password"
  label="Password"
  type={showPassword ? "text" : "password"}  // ← CHANGE THIS LINE (replace "password" with the conditional)
  placeholder="**************"
  data-testid="password"
  endAdornment={  // ← ADD THIS ENTIRE BLOCK (add before the closing />)
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

**📝 STEP-BY-STEP:**
1. Find the `<TextFormField>` component with `name="password"`
2. Find the line that says `type="password"` and change it to: `type={showPassword ? "text" : "password"}`
3. Find the line that says `data-testid="password"` (this should be the last property before the closing `/>`)
4. After `data-testid="password"`, press Enter to create a new line
5. Add a comma after `data-testid="password"` if it doesn't have one
6. Copy and paste this entire block:
   ```typescript
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
   ```
7. Make sure the closing `/>` is on a new line after the `endAdornment` block

---

## Summary

After applying these changes:

1. ✅ The `TextFormField` component now accepts an optional `endAdornment` prop that can render any React node (like a button) inside the input field.
2. ✅ The login form tracks password visibility state and toggles between showing/hiding the password.
3. ✅ Users can click the eye icon to reveal or mask their password while typing.

---

## Deployment Checklist

1. Apply the code changes in `onyx-repo`.
2. Build the web app (`pnpm build` or your CI pipeline).
3. Redeploy the frontend.

**No backend changes required.** The pattern is reusable for other forms that need a toggle or trailing button inside the input field.
