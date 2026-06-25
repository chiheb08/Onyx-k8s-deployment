# OpenShift Deployment-Architektur (CI/CD) — mit LiteLLM-Gateway

Architekturdiagramm für **chat.Bai V2.0** auf OpenShift: GitHub, Artifactory, Build Pipeline, ArgoCD, Application — plus **LiteLLM** als LLM-Gateway im Cluster.

> **Laufzeit / Chat-Flow:** [INTERFACE-DIAGRAM-chatBai-V2-LITELLM.de.md](./INTERFACE-DIAGRAM-chatBai-V2-LITELLM.de.md)  
> **English:** [ARCHITECTURE-DIAGRAM-OPENSHIFT-CICD-LITELLM.md](./ARCHITECTURE-DIAGRAM-OPENSHIFT-CICD-LITELLM.md)

---

## Kurzüberblick (was sich ändert)

**Vorher:** Application bezog LLMs direkt von **Extern / Internet** (`Bezug LLMs`).

**Nachher:** Application ruft **LiteLLM Gateway** im OpenShift auf. LiteLLM leitet an **vLLM** weiter. Modell-Gewichte / Images weiter über **Artifactory** oder freigegebene externe Quellen.

```
  VORHER:  Application ──────────► Extern/Internet (LLMs)

  NACHHER: Application ──► LiteLLM Gateway ──► vLLM Server
                                ▲
                                └── Modell-Konfiguration
                                    (Artifactory oder Extern)
```

---

## Gesamtdiagramm (ASCII)

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Artifactory   │     │ Extern /        │     │    GitHub       │
│                 │     │ Internet        │     │                 │
│ Ablage Build-   │◄────│ Ablage Build-   │     │ Application     │
│ dependencies    │     │ dependencies    │     │ Code            │
│ Containerimages │────►│ Bezug Container-│     │                 │
└────────┬────────┘     │ images          │     └────────┬────────┘
         │              └────────┬────────┘              │
         │ Bezug von             │                       │ Definition
         │ Builddependencies     │                       │ OpenShift
         │                       │                       │ Komponenten
         │                       │                       │
         ▼                       ▼                       ▼
┌────────────────────────────────────────────────────────────────────────┐
│                         OPENSHIFT CLUSTER                              │
│                                                                        │
│  ┌──────────────────┐         ┌──────────────────────────────────┐  │
│  │  Build Pipeline  │         │  Application (chat.Bai V2.0)     │  │
│  │                  │────────►│  API, Web, Worker, OpenSearch…   │  │
│  └────────┬─────────┘         └───────────────┬──────────────────┘  │
│           │                                   │ LLM-API              │
│           │ Ablage erstellter                 ▼                      │
│           │ Containerimages    ┌──────────────────────────────┐    │
│           ▼                    │  LiteLLM Gateway  ★ NEU ★     │    │
│      (→ Artifactory)           │  Routing, Auth, Logging       │    │
│                                └──────────────┬───────────────┘    │
│                                               ▼                      │
│                                ┌──────────────────────────────┐    │
│                                │  vLLM Server                 │    │
│                                └──────────────┬───────────────┘    │
│                                               ▼                      │
│                                ┌──────────────────────────────┐    │
│                                │  Modell-Speicher (PVC)       │    │
│                                └──────────────────────────────┘    │
│                                                                        │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │  ArgoCD — Deployment aller Komponenten inkl. LiteLLM + vLLM    │  │
│  └────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘

Bezug LLMs / Modell-Artefakte  →  LiteLLM + vLLM  (nicht mehr direkt → Application)
```

---

## Mermaid-Diagramm

```mermaid
flowchart TB
  subgraph External[Außerhalb OpenShift]
    AF[(Artifactory)]
    EXT[(Extern / Internet)]
    GH[(GitHub)]
  end

  subgraph OCP[OpenShift Cluster]
    BP[Build Pipeline]
    APP[Application<br/>chat.Bai V2.0]
    LIT[LiteLLM Gateway<br/>★ NEU ★]
    VLLM[vLLM Server]
    MS[(Modell-Speicher PVC)]
    ARGO[ArgoCD<br/>GitOps Deployment]

    BP --> APP
    APP -->|LLM-API| LIT
    LIT --> VLLM
    VLLM --> MS
  end

  GH -->|Application Code| BP
  GH -->|Definition OpenShift<br/>Komponenten| ARGO

  EXT -->|Ablage Builddependencies| AF
  AF -->|Bezug Builddependencies| BP
  BP -->|Ablage Containerimages| AF
  AF -->|Bezug Containerimages| APP

  AF -->|Bezug LLMs /<br/>LiteLLM-Konfiguration| LIT
  EXT -.->|freigegebener Modell-Download| AF

  ARGO -->|Deployment| BP
  ARGO -->|Deployment| APP
  ARGO -->|Deployment| LIT
  ARGO -->|Deployment| VLLM
```

---

## Komponenten

| Komponente | Rolle | Änderung |
|------------|-------|----------|
| GitHub | Code + Manifeste | unverändert |
| Artifactory | Dependencies, Images, Modell-Artefakte | unverändert |
| Extern / Internet | Kein direkter LLM-Pfad mehr zur Application | **angepasst** |
| Build Pipeline | Images bauen | unverändert |
| Application | chat.Bai Laufzeit | unverändert |
| **LiteLLM Gateway** | LLM-API-Gateway | **neu** |
| vLLM Server | GPU-Inferenz | explizit dargestellt |
| ArgoCD | GitOps | deployt auch LiteLLM |

---

## Datenflüsse (Original-Bezeichnungen)

| Bezeichnung | Von → Nach | Status |
|-------------|------------|--------|
| Application Code | GitHub → Build Pipeline | unverändert |
| Definition OpenShift Komponenten | GitHub → ArgoCD | + LiteLLM-Manifeste |
| Bezug Builddependencies | Artifactory → Build Pipeline | unverändert |
| Ablage Containerimages | Build Pipeline → Artifactory | unverändert |
| Bezug Containerimages | Artifactory → Application | unverändert |
| ~~Bezug LLMs → Application~~ | — | **entfernt** |
| Bezug LLMs | Artifactory/Extern → LiteLLM, vLLM | **neu** |
| LLM-API | Application → LiteLLM → vLLM | **neu** |
| Deployment | ArgoCD → alle Workloads | + LiteLLM |

---

## GitHub / ArgoCD — was ergänzen

```text
litellm-integration/manifests/
implementation/openshift/manifests/
```

Siehe [litellm-integration/LITELLM-DEPLOYMENT-GUIDE.md](../litellm-integration/LITELLM-DEPLOYMENT-GUIDE.md).

---

*Stand: Juni 2026 — OpenShift CI/CD mit LiteLLM-Gateway*
