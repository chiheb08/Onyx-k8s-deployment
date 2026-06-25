# chat.Bai V2.0 — Architekturdiagramm (mit LiteLLM-Gateway)

Vereinfachte Architektur für chat.Bai V2.0: Login, Reverse-Proxy, API, Session-Cache, Chat-UI, Chatbot-System (Retrieval + Generierung), **LiteLLM-Gateway**, vLLM-Server und Modell-Speicher.

> **Änderung gegenüber V1:** LLM-Anfragen gehen nicht mehr direkt vom Chatbot-System zum vLLM-Server. Sie laufen über den **LiteLLM Proxy** (OpenAI-kompatibles Gateway) für Routing, Authentifizierung, Retries und einheitlichen Modellzugriff.

---

## Übersicht (einfaches Diagramm)

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────┐
│  Log In UI  │────►│ Reverse-     │────►│ API Server  │────►│ Datenbank│
│             │     │ Proxy        │     │ (Hash/      │     │ Benutzer │
└─────────────┘     └──────────────┘     │ Validierung)│     └──────────┘
                                         └──────┬──────┘
                                                │
                                                ▼
                                         ┌──────────────┐
                                         │ Cache        │
                                         │ (Sitzungen)  │
                                         └──────┬───────┘
                                                │
                                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│  chat.Bai V2.0 — Chat-UI (Projekte, Verlauf, Eingabefeld)            │
└───────────────────────────────┬──────────────────────────────────────┘
                                │ Chat-Anfrage
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Chatbot-System                                                      │
│  Logik → Retrieval (embed + search) → Antwort generieren             │
│       → LiteLLM Gateway → vLLM → Antwort aufbereiten → UI            │
└──────────────────────────────────────────────────────────────────────┘

        Antwort generieren ──►  LiteLLM Gateway  ──►  vLLM Server
                                      │                    │
                                      └────────┬───────────┘
                                               ▼
                                        Modell-Speicher
                                        (LLM-Gewichte)
```

---

## Detailliertes Mermaid-Diagramm

```mermaid
flowchart TB
  subgraph Login[Log In UI]
    U[E-Mail / Benutzername]
    P[Passwort]
    BTN[Anmelden]
  end

  RP[Reverse-Proxy<br/>NGINX / OpenShift Route]

  subgraph Creds[API Server]
    HASH[Credential-Hashing<br/>und Validierung]
  end

  DB[(Datenbank<br/>Benutzertabelle)]
  Cache[(Cache<br/>Sitzungserstellung)]

  subgraph App[chat.Bai V2.0]
    subgraph UI[Chat-Oberfläche]
      Sidebar[Projekte / Verlauf]
      ChatBox[Chat-Nachrichten]
      Input[Wie kann ich behilflich sein?]
      Submit[Senden]
    end
  end

  subgraph Chatbot[Chatbot-System]
    Logic[Chatbot-Logik]
    Retrieval[Retrieval: Embedding + Suche]
    Generate[Antwort generieren]
    PostProcess[Antwort aufbereiten]
  end

  subgraph Gateway[LiteLLM Gateway]
    LProxy[LiteLLM Proxy<br/>OpenAI-kompatible API]
    LRoute[Modell-Routing / Auth / Retries]
  end

  subgraph VLLM[vLLM Server]
    Serve[Modelle bereitstellen]
    Infer[Token-Inferenz]
  end

  subgraph Models[Modell-Speicher]
    MStore[(Große Sprachmodelle<br/>Qwen, GLM, ...)]
  end

  PG[(PostgreSQL)]
  Redis[(Redis)]
  Index[(OpenSearch / Vektorindex)]
  S3[(MinIO / S3)]
  Embed[Embeddings-Inferenz-Server]

  U --> BTN
  P --> BTN
  BTN -->|Login-Anfrage| RP
  RP --> HASH
  HASH --> DB
  HASH --> Cache
  Cache --> App

  Input --> Submit
  Submit -->|Chat-Anfrage| Logic
  Logic --> Retrieval
  Retrieval --> Embed
  Embed --> Retrieval
  Retrieval --> Index
  Index --> Retrieval
  Retrieval --> Generate

  Generate -->|LLM-Anfrage| LProxy
  LProxy --> LRoute
  LRoute --> Serve
  Serve --> Infer
  Infer --> MStore
  Infer --> LRoute
  LRoute --> LProxy
  LProxy --> Generate

  Generate --> PostProcess
  PostProcess --> ChatBox

  Logic --> PG
  PostProcess --> PG
  UI --> Redis
```

---

## Rolle von LiteLLM

| Aspekt | Ohne LiteLLM | Mit LiteLLM-Gateway |
|--------|--------------|---------------------|
| API → LLM | Direkt zu vLLM | API → LiteLLM → vLLM |
| Modellliste | Ein Endpoint pro Pool | Eine LiteLLM-URL, Routing zu Qwen/GLM |
| Authentifizierung | Pro Dienst | Zentraler `LITELLM_MASTER_KEY` |
| Retries | In App | LiteLLM-Konfiguration |
| Monitoring | Nur vLLM-Logs | LiteLLM-Metriken + Request-Logs |

**Typische interne URL (OpenShift):**

```text
http://litellm-proxy.onyx-infra.svc.cluster.local:4000
```

---

## Komponenten

| Komponente | Status | Zweck |
|------------|--------|-------|
| Log In UI | unverändert | Anmeldung |
| Reverse-Proxy | unverändert | TLS, Routing, Timeouts |
| API Server | unverändert | Logik, Auth, Chat-Orchestrierung |
| Datenbank | unverändert | Benutzer, Metadaten |
| Cache | unverändert | Sitzungen (Redis) |
| chat.Bai V2.0 UI | unverändert | Projekte, Verlauf, Chat |
| Chatbot-System | unverändert | Logik, Retrieval, Antwort |
| **LiteLLM Gateway** | **neu** | LLM-API-Gateway |
| vLLM Server | unverändert | GPU-Inferenz |
| Modell-Speicher | unverändert | Modellgewichte |

---

## Verwandte Dokumente

- [INTERFACE-DIAGRAM-chatBai-V2-LITELLM.md](./INTERFACE-DIAGRAM-chatBai-V2-LITELLM.md) — English version
- [litellm-integration/LITELLM-DEPLOYMENT-GUIDE.md](../litellm-integration/LITELLM-DEPLOYMENT-GUIDE.md)

---

*Stand: Juni 2026 — chat.Bai V2.0 mit LiteLLM-Gateway*
