# Onyx Interface Diagram (Simplified, vLLM)

The following diagram mirrors the attached example: login pane on the left, main app/chat UI, user credentials box, model storage, vLLM server, and chatbot system with request/response loops. Only key components are shown.

```mermaid
flowchart LR
  %% Sections (as big groups) %%
  subgraph Login[Login to Onyx]
    TOS[Terms & Conditions]
    Agree[I agree to the terms]
    U[Username]
    P[Password]
    BTN[Login]
  end

  subgraph App[chat.Onyx]
    SelectModel[Select Model]
    Logout[Logout]
    subgraph UI[Chat UI]
      ChatBox["Chat box<br/>assistant & user"]
      Input["Enter your query..."]
      SubmitBtn[Submit]
    end
  end

  subgraph Creds[User Credentials]
    ENV["Store (PostgreSQL)<br/>users, roles, orgs"]
    HASH["Credential hashing & validation<br/>FastAPI"]
  end

  subgraph Models[Storage: Large Language Models]
    M1[Llama 3.x]
    M2[Other models]
  end

  subgraph VLLM[vLLM Server]
    RunVLLM[Run vLLM]
    ServeVLLM[Serve models]
  end

  subgraph Chatbot[Chatbot System]
    Logic[Chatbot Logic]
    Retrieval[Retrieval: embed + search]
    Generate[Generate Response - vLLM]
    PostProcess[Process Response]
  end

  %% External infra boxes
  Redis[(Redis: sessions + broker)]
  PG[(PostgreSQL: metadata, chat history)]
  Index[(pgvector/Vespa: vector index)]
  S3[(Private S3: file storage)]
  Embed["Embeddings Inference Server"]

  %% Login wiring
  U -->|credentials| BTN
  P -->|credentials| BTN
  Agree -.-> BTN
  TOS -.-> BTN

  BTN -- Login Request --> App
  BTN -. Validate via API .-> HASH
  HASH --> ENV
  HASH --> Redis

  %% App wiring
  SelectModel --> UI
  Logout --> UI

  %% Chat request path
  Input --> SubmitBtn
  SubmitBtn -- Chat Request --> Logic
  Logic --> Retrieval
  Retrieval -->|query text| Embed
  Embed -->|query embedding| Retrieval
  Retrieval --> Index
  Index -->|top-k context| Retrieval
  Retrieval --> Generate
  Generate -->|LLM request| VLLM
  VLLM --> ServeVLLM
  ServeVLLM --> RunVLLM
  RunVLLM -->|tokens| Generate
  Generate --> Process
  PostProcess -- Chat Response --> ChatBox
  ChatBox -. Display Response .- UI

  %% Persistence and sessions
  Logic --> PG
  PostProcess --> PG
  ENV --> PG
  UI -->|session| Redis

  %% Files & indexing (optional)
  UI -. file upload .-> S3
  S3 -. async indexing via workers .-> Index

  %% Model storage reference
  Models --> VLLM
```

Notes:
- User credentials are stored in PostgreSQL; validation and hashing are done by the API (FastAPI). Sessions are maintained in Redis.
- Retrieval uses embeddings from the Embeddings Inference Server and vector search via pgvector or Vespa.
- Generation is performed by vLLM (replacing Ollama). The UI receives streamed tokens and renders progressively.
- Optional: file uploads go to Private S3 and are indexed asynchronously by workers into pgvector/Vespa.
