# Frontend Technologies Used in Onyx

This document provides a comprehensive overview of all technologies, frameworks, libraries, and tools used in the Onyx frontend application.

---

## Technology Stack Overview

| Category | Technology | Version | Purpose |
|----------|-----------|---------|---------|
| **Core Framework** | Next.js | ^15.5.2 | React-based full-stack framework for server-side rendering, routing, and API routes |
| **UI Library** | React | ^18.3.1 | JavaScript library for building user interfaces and components |
| **UI Library** | React DOM | ^18.3.1 | React renderer for web browsers |
| **Language** | TypeScript | 5.0.3 | Typed superset of JavaScript for type safety and better developer experience |
| **Styling** | Tailwind CSS | ^3.3.1 | Utility-first CSS framework for rapid UI development |
| **Styling** | PostCSS | ^8.4.31 | CSS post-processor for transforming CSS with JavaScript plugins |
| **Styling** | Autoprefixer | ^10.4.14 | PostCSS plugin to automatically add vendor prefixes to CSS |
| **Styling** | Tailwind CSS Animate | ^1.0.7 | Animation utilities for Tailwind CSS |
| **Styling** | Tailwind Typography | ^0.5.10 | Typography plugin for Tailwind CSS (dev dependency) |

---

## UI Component Libraries

| Technology | Version | Purpose |
|-----------|---------|---------|
| **Radix UI** | Multiple packages | Headless, accessible component primitives for building custom UI components |
| `@radix-ui/react-accordion` | ^1.2.2 | Collapsible accordion component |
| `@radix-ui/react-avatar` | ^1.1.10 | Avatar/image component |
| `@radix-ui/react-checkbox` | ^1.3.3 | Checkbox input component |
| `@radix-ui/react-collapsible` | ^1.1.2 | Collapsible content component |
| `@radix-ui/react-dialog` | ^1.1.6 | Modal dialog component |
| `@radix-ui/react-dropdown-menu` | ^2.1.6 | Dropdown menu component |
| `@radix-ui/react-hover-card` | ^1.1.15 | Hover card/tooltip component |
| `@radix-ui/react-label` | ^2.1.1 | Accessible label component |
| `@radix-ui/react-menubar` | ^1.1.16 | Menu bar component |
| `@radix-ui/react-popover` | ^1.1.6 | Popover component |
| `@radix-ui/react-radio-group` | ^1.2.2 | Radio button group component |
| `@radix-ui/react-scroll-area` | ^1.2.2 | Custom scrollable area component |
| `@radix-ui/react-select` | ^2.1.6 | Select dropdown component |
| `@radix-ui/react-separator` | ^1.1.0 | Visual separator component |
| `@radix-ui/react-slider` | ^1.2.2 | Slider/range input component |
| `@radix-ui/react-slot` | ^1.1.2 | Slot component for composition |
| `@radix-ui/react-switch` | ^1.1.3 | Toggle switch component |
| `@radix-ui/react-tabs` | ^1.1.1 | Tab navigation component |
| `@radix-ui/react-tooltip` | ^1.1.3 | Tooltip component |
| **Headless UI** | ^2.2.0 | Unstyled, accessible UI components |
| **Headless UI Tailwind** | ^0.2.1 | Tailwind CSS integration for Headless UI |

---

## Icon Libraries

| Technology | Version | Purpose |
|-----------|---------|---------|
| Phosphor Icons | ^2.0.8 | Icon library with React components |
| Lucide React | ^0.454.0 | Icon library with React components |
| React Icons | ^4.8.0 | Popular icon library aggregator |

---

## Form Management & Validation

| Technology | Version | Purpose |
|-----------|---------|---------|
| Formik | ^2.2.9 | Form state management library |
| Yup | ^1.4.0 | Schema validation library (works with Formik) |

---

## State Management

| Technology | Version | Purpose |
|-----------|---------|---------|
| Zustand | ^5.0.7 | Lightweight state management library |
| SWR | ^2.1.5 | Data fetching library with caching and revalidation |

---

## Data Fetching & HTTP

| Technology | Version | Purpose |
|-----------|---------|---------|
| SWR | ^2.1.5 | React hooks for data fetching with caching |
| Cookies Next | ^5.1.0 | Cookie management for Next.js |
| JS Cookie | ^3.0.5 | Simple cookie handling library |

---

## Drag & Drop

| Technology | Version | Purpose |
|-----------|---------|---------|
| @dnd-kit/core | ^6.1.0 | Modern drag-and-drop toolkit for React |
| @dnd-kit/sortable | ^8.0.0 | Sortable list components |
| @dnd-kit/modifiers | ^7.0.0 | Drag-and-drop modifiers |
| @dnd-kit/utilities | ^3.2.2 | Utility functions for dnd-kit |

---

## Markdown & Content Rendering

| Technology | Version | Purpose |
|-----------|---------|---------|
| React Markdown | ^9.0.1 | React component for rendering Markdown |
| Remark GFM | ^4.0.0 | GitHub Flavored Markdown support |
| Remark Math | ^6.0.0 | Math equation support in Markdown |
| Rehype Highlight | ^7.0.2 | Syntax highlighting for code blocks |
| Rehype KaTeX | ^7.0.1 | Math rendering with KaTeX |
| Rehype Sanitize | ^6.0.0 | HTML sanitization for security |
| Rehype Stringify | ^10.0.1 | HTML stringifier for rehype |
| Highlight.js | ^11.11.1 | Syntax highlighting library |
| Lowlight | ^3.3.0 | Highlight.js integration for unified |
| KaTeX | ^0.16.17 | Math typesetting library |
| MDast Util Find and Replace | ^3.0.1 | Markdown AST manipulation utilities |

---

## Data Tables & Visualization

| Technology | Version | Purpose |
|-----------|---------|---------|
| TanStack React Table | ^8.21.3 | Headless table library for React |
| Recharts | ^2.13.1 | Charting library for React |

---

## Date & Time

| Technology | Version | Purpose |
|-----------|---------|---------|
| Date-fns | ^3.6.0 | Date utility library |
| React Datepicker | ^7.6.0 | Date picker component |
| React Day Picker | ^8.10.1 | Calendar component |

---

## File Handling

| Technology | Version | Purpose |
|-----------|---------|---------|
| React Dropzone | ^14.2.3 | File upload component with drag-and-drop |

---

## Utilities & Helpers

| Technology | Version | Purpose |
|-----------|---------|---------|
| Lodash | ^4.17.21 | JavaScript utility library |
| CLSX | ^2.1.1 | Utility for constructing className strings |
| Tailwind Merge | ^2.5.4 | Merge Tailwind CSS classes intelligently |
| Class Variance Authority | ^0.7.0 | Component variant management |
| UUID | ^9.0.1 | Generate unique identifiers |
| Semver | ^7.5.4 | Semantic versioning parser |

---

## Command Palette & Search

| Technology | Version | Purpose |
|-----------|---------|---------|
| CMDK | ^1.0.0 | Command menu component (like VS Code command palette) |

---

## Payment Processing

| Technology | Version | Purpose |
|-----------|---------|---------|
| Stripe | ^17.0.0 | Payment processing library (server-side) |
| @stripe/stripe-js | ^4.6.0 | Stripe.js for client-side payment integration |

---

## Monitoring & Analytics

| Technology | Version | Purpose |
|-----------|---------|---------|
| Sentry Next.js | ^10.9.0 | Error tracking and performance monitoring |
| Sentry Tracing | ^7.120.3 | Performance tracing for Sentry |
| PostHog JS | ^1.176.0 | Product analytics and feature flags |

---

## Theming

| Technology | Version | Purpose |
|-----------|---------|---------|
| Next Themes | ^0.4.4 | Dark/light mode theme switching |

---

## UI Components & Drawers

| Technology | Version | Purpose |
|-----------|---------|---------|
| Vaul | ^1.1.1 | Drawer component library |

---

## Image Processing

| Technology | Version | Purpose |
|-----------|---------|---------|
| Sharp | ^0.33.5 | High-performance image processing library |
| Favicon Fetch | ^1.0.0 | Fetch and process favicons |

---

## Loading & Spinners

| Technology | Version | Purpose |
|-----------|---------|---------|
| React Loader Spinner | ^5.4.5 | Loading spinner components |

---

## Testing Frameworks

| Technology | Version | Purpose |
|-----------|---------|---------|
| Jest | ^29.7.0 | JavaScript testing framework |
| TS Jest | ^29.2.5 | TypeScript preprocessor for Jest |
| Jest Environment JSDOM | ^29.7.0 | DOM environment for Jest tests |
| React Testing Library | ^14.3.1 | Testing utilities for React components |
| Testing Library User Event | ^14.6.1 | Simulate user interactions in tests |
| Testing Library Jest DOM | ^6.9.1 | Custom Jest matchers for DOM testing |
| Playwright | ^1.39.0 | End-to-end testing framework |
| Chromatic | ^11.25.2 | Visual regression testing and component documentation |

---

## Code Quality & Linting

| Technology | Version | Purpose |
|-----------|---------|---------|
| ESLint | ^8.57.1 | JavaScript/TypeScript linter |
| ESLint Config Next | ^14.1.0 | Next.js ESLint configuration |
| ESLint Plugin Unused Imports | ^4.1.4 | Detect and remove unused imports |
| Prettier | 3.1.0 | Code formatter |
| TS Unused Exports | ^11.0.1 | Detect unused TypeScript exports |

---

## Type Definitions

| Technology | Version | Purpose |
|-----------|---------|---------|
| @types/node | 18.15.11 | TypeScript definitions for Node.js |
| @types/react | 18.0.32 | TypeScript definitions for React |
| @types/react-dom | 18.0.11 | TypeScript definitions for React DOM |
| @types/jest | ^29.5.14 | TypeScript definitions for Jest |
| @types/js-cookie | ^3.0.6 | TypeScript definitions for js-cookie |
| @types/lodash | ^4.17.20 | TypeScript definitions for Lodash |
| @types/uuid | ^9.0.8 | TypeScript definitions for UUID |
| @types/chrome | ^0.0.287 | TypeScript definitions for Chrome extensions |
| @types/hast | ^3.0.4 | TypeScript definitions for HAST (HTML AST) |

---

## Build & Development Tools

| Technology | Version | Purpose |
|-----------|---------|---------|
| Next.js Turbo | Built-in | Fast build system for Next.js (via `--turbo` flag) |
| Identity Obj Proxy | ^3.0.0 | Proxy for CSS modules in Jest tests |
| WhatWG Fetch | ^3.6.20 | Fetch API polyfill for Node.js (testing) |

---

## Summary by Category

### **Core Stack**
- **Framework**: Next.js 15.5.2 (React 18.3.1)
- **Language**: TypeScript 5.0.3
- **Styling**: Tailwind CSS 3.3.1 with PostCSS and Autoprefixer

### **UI Components**
- **Component Libraries**: Radix UI (20+ components), Headless UI, Lucide/Phosphor Icons
- **Form Management**: Formik + Yup
- **State Management**: Zustand + SWR

### **Content & Media**
- **Markdown**: React Markdown with GFM, Math, and syntax highlighting
- **Charts**: Recharts
- **Tables**: TanStack React Table
- **Images**: Sharp for processing

### **Developer Experience**
- **Testing**: Jest + React Testing Library + Playwright + Chromatic
- **Linting**: ESLint + Prettier
- **Type Safety**: TypeScript with comprehensive type definitions

### **Production Features**
- **Monitoring**: Sentry for error tracking
- **Analytics**: PostHog for product analytics
- **Payments**: Stripe integration
- **Theming**: Dark/light mode support

---

## Technology Choices Rationale

1. **Next.js**: Provides server-side rendering, API routes, and optimized performance out of the box.
2. **TypeScript**: Ensures type safety and reduces runtime errors in a large codebase.
3. **Tailwind CSS**: Enables rapid UI development with utility classes and consistent design system.
4. **Radix UI**: Provides accessible, unstyled components that can be customized with Tailwind.
5. **Zustand**: Lightweight alternative to Redux for simple state management needs.
6. **SWR**: Handles data fetching, caching, and revalidation automatically.
7. **Formik + Yup**: Industry-standard form handling and validation solution.
8. **Jest + Playwright**: Comprehensive testing strategy covering unit, integration, and E2E tests.

---

This technology stack provides a modern, scalable, and maintainable foundation for building a complex enterprise application like Onyx.

