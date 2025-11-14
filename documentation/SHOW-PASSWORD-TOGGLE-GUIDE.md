# Show/Hide Password Toggle – Implementation Guide

This guide provides step-by-step instructions with exact code comparisons (old vs. new) for adding a show/hide password toggle to the Onyx login form.

---

## Overview

| Area | File | Purpose |
|------|------|---------|
| Shared form field | `web/src/components/Field.tsx` | Allow inputs to render a right-aligned control (`endAdornment`). |
| Login form | `web/src/app/auth/login/EmailPasswordForm.tsx` | Show/hide password logic using the new prop. |

---

## Step 1 – Enhance `TextFormField` Component

**File:** `web/src/components/Field.tsx`

**Location:** Find the imports section at the top of the file (around line 32-39).

### 1.1 Add `ReactNode` to React Imports

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
  ReactNode,
} from "react";
```

---

**Location:** Find the `TextFormField` function definition (around line 223-279). Look for the function parameters and type definition.

### 1.2 Add `endAdornment` Prop to Function Parameters

--- old ---
```typescript
export function TextFormField({
  name,
  label,
  subtext,
  placeholder,
  type = "text",
  optional,
  includeRevert,
  isTextArea = false,
  disabled = false,
  autoCompleteDisabled = true,
  // ... other props ...
  className,
}: {
  name: string;
  // ... other type definitions ...
  className?: string;
})
```

--- new ---
```typescript
export function TextFormField({
  name,
  label,
  subtext,
  placeholder,
  type = "text",
  optional,
  includeRevert,
  isTextArea = false,
  disabled = false,
  autoCompleteDisabled = true,
  // ... other props ...
  className,
  endAdornment,
}: {
  name: string;
  // ... other type definitions ...
  className?: string;
  endAdornment?: ReactNode;
})
```

---

**Location:** Find the input element inside `TextFormField` (around line 360-381). Look for the `<input>` or `<textarea>` element and its className.

### 1.3 Add Padding for Adornment and Render It

--- old ---
```typescript
<input
  data-testid={name}
  name={name}
  id={name}
  className={`
    ${small && sizeClass.input}
    flex
    h-10
    w-full
    rounded-md
    border
    px-3
    py-2
    mt-1
    file:border-0
    file:bg-transparent
    file:text-sm
    file:font-medium
    file:text-foreground
    placeholder:text-text-03
    focus-visible:outline-none
    focus-visible:ring-2
    focus-visible:ring-ring
    disabled:cursor-not-allowed
    disabled:opacity-50
    ${heightString}
    ${sizeClass.input}
    ${disabled ? "bg-background-neutral-02" : ""}
    ${isCode ? "font-mono" : ""}
    ${className}
    bg-background-neutral-00
  `}
  disabled={disabled}
  placeholder={placeholder}
  autoComplete={autoCompleteDisabled ? "off" : undefined}
/>
```

--- new ---
```typescript
<input
  data-testid={name}
  name={name}
  id={name}
  className={`
    ${small && sizeClass.input}
    flex
    h-10
    w-full
    rounded-md
    border
    px-3
    ${endAdornment ? "pr-10" : ""}
    py-2
    mt-1
    file:border-0
    file:bg-transparent
    file:text-sm
    file:font-medium
    file:text-foreground
    placeholder:text-text-03
    focus-visible:outline-none
    focus-visible:ring-2
    focus-visible:ring-ring
    disabled:cursor-not-allowed
    disabled:opacity-50
    ${heightString}
    ${sizeClass.input}
    ${disabled ? "bg-background-neutral-02" : ""}
    ${isCode ? "font-mono" : ""}
    ${className}
    bg-background-neutral-00
  `}
  disabled={disabled}
  placeholder={placeholder}
  autoComplete={autoCompleteDisabled ? "off" : undefined}
/>
{endAdornment && (
  <div className="absolute inset-y-0 right-3 flex items-center">
    {endAdornment}
  </div>
)}
```

**Note:** The input wrapper (`<div>`) should have `position: relative` for the absolute positioning to work. Make sure the parent div has `relative` class if it doesn't already.

---

## Step 2 – Add Toggle to Login Form

**File:** `web/src/app/auth/login/EmailPasswordForm.tsx`

**Location:** Find the imports section at the top of the file (around line 1-15).

### 2.1 Import Eye Icons

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
import { FiEye, FiEyeOff } from "react-icons/fi";
```

---

**Location:** Find the component function body, right after the `useState` hooks (around line 34-37).

### 2.2 Add Password Visibility State

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
  const [showPassword, setShowPassword] = useState<boolean>(false);

  const togglePasswordVisibility = () => {
    setShowPassword((prev) => !prev);
  };
```

---

**Location:** Find the password `TextFormField` inside the `<Form>` component (around line 152-168).

### 2.3 Update Password Field with Toggle

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
