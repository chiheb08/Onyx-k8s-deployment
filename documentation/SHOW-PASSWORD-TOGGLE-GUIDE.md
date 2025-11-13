# Adding a “Show Password” Toggle to Onyx Login

This note documents every code change needed to add a show/hide password button on the login form (and any other password field that uses the shared `TextFormField`).

---

## 1. Update `TextFormField` (shared field component)
**File:** `web/src/components/Field.tsx`

1. **Extend React imports**
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

2. **Add new prop to the component signature**
   ```diff
 export function TextFormField({
   ...
-  className,
+  className,
+  endAdornment,
 }: {
   ...
-  className?: string;
+  className?: string;
+  endAdornment?: ReactNode;
 }) {
   ```

3. **Adjust the input wrapper to reserve space and render the adornment**
   ```diff
   <div className={`w-full flex ${includeRevert && "gap-x-2"} relative`}>
     <Field
       ...
-      className={`
+      className={`
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
   </div>
   ```

This makes the field capable of accepting any control (buttons, icons, etc.) on the right-hand side.

---

## 2. Update the login form
**File:** `web/src/app/auth/login/EmailPasswordForm.tsx`

1. **Import toggle icons**
   ```ts
   import { FiEye, FiEyeOff } from "react-icons/fi";
   ```

2. **Add component state**
   ```ts
   const [showPassword, setShowPassword] = useState(false);
   const togglePasswordVisibility = () => setShowPassword((prev) => !prev);
   ```

3. **Replace the password field with a toggle-aware version**
   ```diff
   <TextFormField
     name="password"
     label="Password"
-    type="password"
+    type={showPassword ? "text" : "password"}
     placeholder="**************"
     data-testid="password"
+    endAdornment={
+      <button
+        type="button"
+        onClick={togglePasswordVisibility}
+        aria-label={showPassword ? "Hide password" : "Show password"}
+        className="text-text-03 hover:text-text-04 focus:outline-none"
+      >
+        {showPassword ? <FiEyeOff size={16} /> : <FiEye size={16} />}
+      </button>
+    }
   />
   ```

---

## 3. Result
- Any form using `TextFormField` can now render a right-aligned control via `endAdornment`.
- The login screen displays an eye / eye-slash icon that toggles password visibility.
- No backend changes required; the update lives entirely in the Next.js frontend.

---

## 4. Deployment checklist
1. Apply the code changes in `onyx-repo`.
2. Build the web app (`pnpm build` or your deployment pipeline).
3. Redeploy the frontend so users see the toggle.

These steps match the code modifications already committed to the web repo. Use this guide as the canonical reference for reproducing or backporting the change.
