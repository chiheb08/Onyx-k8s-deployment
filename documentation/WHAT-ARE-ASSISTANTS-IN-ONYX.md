# What Are Assistants in Onyx?

This document explains what assistants are in Onyx, how they work, and how to use them.

---

## Simple Explanation

**Assistants** in Onyx are **customizable AI chat interfaces** that you can configure to behave differently and access different documents. Think of them as different "personalities" or "specialists" for your AI system.

### Real-World Analogy

Imagine you have different employees in your company:
- **HR Assistant**: Specializes in HR policies, employee handbooks, benefits
- **IT Assistant**: Knows about technical documentation, system guides, troubleshooting
- **Sales Assistant**: Has access to sales reports, customer data, product catalogs
- **General Assistant**: Can access everything and answer general questions

In Onyx, **assistants work the same way** - each one can be configured to:
- Access specific documents (document sets)
- Use different instructions (system prompts)
- Have different capabilities (tools)
- Use different AI models

---

## Key Concepts

### Assistants = Personas

**Important:** In Onyx's codebase, assistants are called **"Personas"** in the database and backend code. They're the same thing - "assistant" is just the user-friendly name.

- **Frontend/UI**: Calls them "Assistants"
- **Backend/Database**: Calls them "Personas"
- **OpenAI API Compatibility**: Onyx provides an `/assistants` API endpoint that maps to Personas

---

## What Can You Configure in an Assistant?

### 1. **Name and Description**
- Give your assistant a name (e.g., "HR Specialist", "Technical Support Bot")
- Add a description explaining what it does

### 2. **System Prompt (Instructions)**
- This is the "personality" and behavior instructions for the assistant
- Example: "You are a helpful HR assistant. Always be professional and refer to company policies when answering questions."

### 3. **Document Sets**
- **Which documents the assistant can access**
- You can assign specific document sets to each assistant
- Example: HR Assistant only sees HR documents, IT Assistant only sees IT docs

### 4. **Tools (Capabilities)**
- What the assistant can do beyond just answering questions
- Examples:
  - **Search Tool**: Search the web or internal documents
  - **Image Generation**: Create images (if configured)
  - **Code Execution**: Run code snippets (if configured)
  - **Custom Tools**: Any tools you've created

### 5. **LLM Model**
- Which AI model to use (GPT-4, Claude, vLLM, etc.)
- Each assistant can use a different model

### 6. **Search Settings**
- **Number of chunks**: How many document chunks to retrieve per query
- **Relevance filtering**: Whether to use LLM to filter irrelevant chunks
- **Recency bias**: Prefer newer or older documents
- **Time filters**: Only search documents from a certain time period

### 7. **Visibility and Access**
- **Public**: Available to all users
- **Private**: Only visible to the creator
- **Default**: Automatically added to all users' assistant list
- **Built-in**: System-created assistants that can't be edited

---

## Types of Assistants

### 1. **Built-in Assistants**
- Created by the system during deployment
- Cannot be edited or deleted by users
- Examples: Default assistant, system assistants

### 2. **Default Assistants**
- Created by admins
- Automatically visible to all users
- Can be customized by admins

### 3. **User-Created Assistants**
- Created by individual users
- Only visible to the creator (unless made public)
- Fully customizable

### 4. **Public Assistants**
- Available to all users in the organization
- Can be created by admins or users with permission

---

## How Assistants Work (Technical Flow)

```
┌─────────────────────────────────────────────────────────┐
│              USER SELECTS ASSISTANT                     │
│  "I want to use the HR Assistant"                       │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
        ┌───────────────────────────────┐
        │   ASSISTANT CONFIGURATION     │
        │  (Loaded from Persona table) │
        │                               │
        │  - System prompt              │
        │  - Document sets               │
        │  - Tools                      │
        │  - Model settings             │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   USER ASKS QUESTION          │
        │  "What's the vacation policy?"│
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   DOCUMENT SEARCH             │
        │  (Only searches documents in   │
        │   the assistant's document     │
        │   sets)                       │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   LLM PROCESSING              │
        │  - Uses assistant's system    │
        │    prompt                     │
        │  - Uses assistant's model     │
        │  - Applies assistant's        │
        │    settings                  │
        └──────────┬────────────────────┘
                   │
                   ▼
        ┌───────────────────────────────┐
        │   RESPONSE GENERATED          │
        │  (In the style/context of the  │
        │   selected assistant)         │
        └───────────────────────────────┘
```

---

## Example Use Cases

### Use Case 1: Department-Specific Assistants

**Scenario:** A company wants different assistants for different departments.

**Setup:**
1. **HR Assistant**
   - Document Sets: HR Policies, Employee Handbook, Benefits Guide
   - System Prompt: "You are a professional HR assistant. Always refer to official company policies."
   - Tools: Document Search

2. **IT Assistant**
   - Document Sets: Technical Documentation, System Guides, Troubleshooting Docs
   - System Prompt: "You are a technical support assistant. Provide step-by-step solutions."
   - Tools: Document Search, Code Execution

3. **Sales Assistant**
   - Document Sets: Sales Reports, Product Catalogs, Customer Data
   - System Prompt: "You are a sales assistant. Help with product information and sales strategies."
   - Tools: Document Search

**Result:** Each department gets answers relevant to their domain, without seeing other departments' documents.

---

### Use Case 2: Specialized Roles

**Scenario:** A law firm wants assistants for different legal specialties.

**Setup:**
1. **Contract Assistant**
   - Document Sets: Contract Templates, Legal Precedents (Contracts)
   - System Prompt: "You are a contract law specialist. Focus on contract terms and legal requirements."

2. **Litigation Assistant**
   - Document Sets: Case Law, Court Documents, Litigation Procedures
   - System Prompt: "You are a litigation specialist. Help with case preparation and legal strategies."

**Result:** Lawyers can get specialized help without mixing different legal domains.

---

### Use Case 3: Public vs. Private Assistants

**Scenario:** A company wants some assistants available to everyone, and some private.

**Setup:**
1. **Public "Company Knowledge Base" Assistant**
   - Available to all employees
   - Document Sets: Public company documents
   - System Prompt: "You are a helpful company assistant."

2. **Private "Executive Assistant"**
   - Only visible to executives
   - Document Sets: Confidential documents, executive reports
   - System Prompt: "You are an executive assistant. Maintain confidentiality."

**Result:** Different access levels ensure sensitive information stays private.

---

## How to Create an Assistant

### Via UI (Admin Panel)

1. **Navigate to Admin → Assistants**
2. **Click "Create New Assistant"**
3. **Fill in the form:**
   - Name: "HR Specialist"
   - Description: "Helps with HR-related questions"
   - System Prompt: "You are a helpful HR assistant..."
   - Select Document Sets
   - Select Tools
   - Choose LLM Model
   - Set visibility (Public/Private)
4. **Save**

### Via API (OpenAI-Compatible)

```python
import requests

# Create an assistant
response = requests.post(
    "https://your-onyx-instance.com/api/assistants",
    headers={"Authorization": "Bearer <token>"},
    json={
        "name": "HR Specialist",
        "description": "Helps with HR questions",
        "model": "gpt-4",
        "instructions": "You are a helpful HR assistant...",
        "tools": [{"type": "search"}],
        "file_ids": []
    }
)

assistant_id = response.json()["id"]
```

---

## Assistant Selection in Chat

### How Users Select Assistants

1. **Default Assistant**: Automatically selected when starting a new chat
2. **Assistant Switcher**: Users can switch assistants in the chat interface
3. **Pinned Assistants**: Users can pin favorite assistants for quick access
4. **Hidden Assistants**: Users can hide assistants they don't use

### Assistant Priority Order

When a chat session doesn't have a specific assistant selected, Onyx uses this priority:

1. **Selected Assistant** (if user explicitly selected one)
2. **Unified Assistant** (ID 0, if available)
3. **First Pinned Assistant**
4. **First Available Assistant**

---

## Database Structure

### Persona Table (Assistants)

```sql
CREATE TABLE persona (
    id INTEGER PRIMARY KEY,
    user_id UUID,  -- Creator/owner
    name VARCHAR,
    description VARCHAR,
    system_prompt TEXT,  -- Instructions
    task_prompt TEXT,
    num_chunks FLOAT,  -- Number of chunks to retrieve
    llm_relevance_filter BOOLEAN,
    llm_filter_extraction BOOLEAN,
    recency_bias VARCHAR,
    llm_model_provider_override VARCHAR,
    llm_model_version_override VARCHAR,
    builtin_persona BOOLEAN,  -- System-created
    is_default_persona BOOLEAN,  -- Auto-added to all users
    is_visible BOOLEAN,  -- Can users see it?
    is_public BOOLEAN,  -- Available to all?
    deleted BOOLEAN,
    ...
);
```

### Relationships

- **Persona → DocumentSet**: Many-to-many (which documents can the assistant access?)
- **Persona → Tool**: Many-to-many (which tools can the assistant use?)
- **Persona → User**: Many-to-many (which users can access this assistant?)
- **Persona → UserFile**: Many-to-many (which user-uploaded files are attached?)

---

## Key Features

### 1. **Document Isolation**
- Each assistant only searches documents in its assigned document sets
- Ensures users only see relevant information
- Maintains data separation between departments/teams

### 2. **Customizable Behavior**
- System prompts control how the assistant responds
- Different assistants can have different "personalities"
- Example: One assistant is formal, another is casual

### 3. **Tool Integration**
- Assistants can use different tools
- Some assistants might have image generation, others don't
- Custom tools can be created and assigned

### 4. **Model Flexibility**
- Each assistant can use a different LLM model
- Example: HR Assistant uses GPT-4, IT Assistant uses Claude
- Allows cost optimization (use cheaper models where appropriate)

### 5. **Access Control**
- Public assistants: Everyone can use
- Private assistants: Only creator can use
- Group-based access: Assign assistants to specific user groups

---

## Best Practices

### 1. **Organize by Department/Function**
- Create assistants for each department
- Assign relevant document sets
- Use descriptive names

### 2. **Use Clear System Prompts**
- Be specific about the assistant's role
- Include examples of good responses
- Set tone and style expectations

### 3. **Limit Document Sets**
- Don't give assistants access to everything
- Only include documents relevant to their purpose
- Improves search quality and response relevance

### 4. **Test Before Deploying**
- Create assistants and test with sample questions
- Verify they only access intended documents
- Check that responses match the intended style

### 5. **Monitor Usage**
- Track which assistants are used most
- Gather user feedback
- Adjust configurations based on usage patterns

---

## Common Questions

### Q: Can I have multiple assistants active at once?

**A:** No, only one assistant is active per chat session. However, you can switch assistants during a conversation.

### Q: Can assistants share document sets?

**A:** Yes! Multiple assistants can access the same document sets. This is useful when you want different "personalities" accessing the same documents.

### Q: What happens if I delete an assistant?

**A:** The assistant is marked as deleted (soft delete). Existing chat sessions that used it will still work, but new chats won't be able to select it.

### Q: Can I export/import assistants?

**A:** Assistants are stored in the database. You can export the `persona` table data and import it to another Onyx instance.

### Q: How many assistants can I create?

**A:** There's no hard limit, but too many assistants can be confusing for users. Typically, 5-10 assistants per organization is a good number.

---

## Summary

**Assistants in Onyx are:**
- ✅ Customizable AI chat interfaces
- ✅ Configured with specific document sets, prompts, and tools
- ✅ Used to create specialized "personalities" for different use cases
- ✅ Stored as "Personas" in the database
- ✅ Accessible via UI or OpenAI-compatible API

**Key Benefits:**
- 🎯 **Specialization**: Each assistant focuses on specific domains
- 🔒 **Access Control**: Limit which documents each assistant can see
- 🎨 **Customization**: Different behaviors, models, and capabilities
- 👥 **Multi-tenancy**: Different users/teams can have different assistants

**Use Cases:**
- Department-specific assistants (HR, IT, Sales)
- Role-based assistants (Manager, Employee, Admin)
- Project-specific assistants (Project A, Project B)
- Public vs. private assistants

---

This document explains the core concept of assistants in Onyx. For more technical details, see the codebase files:
- `backend/onyx/db/models.py` → `Persona` class
- `backend/onyx/server/openai_assistants_api/asssistants_api.py` → API endpoints
- `web/src/app/admin/assistants/` → UI components

