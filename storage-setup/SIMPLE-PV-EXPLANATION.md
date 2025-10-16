# What is a PV? - Simple Explanation

**A beginner-friendly explanation of PersistentVolume (PV) and how it connects your project to NFS storage**

---

## 🎯 The Simple Answer

A **PersistentVolume (PV)** is like a **"connection card"** that tells Kubernetes:

> "Hey, there's a storage server at this IP address with files we can use!"

**Think of it like a business card:**
- The business card has a **name** (PV name)
- It has an **address** (NFS IP)
- It has a **location** (NFS path)
- It tells you **what's available** (storage size)

---

## 📖 Step-by-Step Simple Explanation

### What Your Colleague Has

Your infrastructure team set up an **NFS Server** (Network File Storage):

```
┌─────────────────────────────────────────┐
│  NFS Server (Physical Storage)         │
│  ─────────────────────────────          │
│  IP Address: 10.100.50.20 (example)     │  ← A computer on the network
│  Directory: /exports/huggingface-models │  ← Folder with files
│  Size: 800 GB                           │  ← Total disk space
│                                         │
│  What's inside:                         │
│  📁 /exports/huggingface-models/        │
│     ├── models--nomic-ai--nomic-...    │  ← AI models (1.5GB)
│     ├── models--mixedbread-ai--...     │  ← AI models (200MB)
│     └── models--onyx-dot-app--...      │  ← AI models (200MB)
│                                         │
│  Total files: ~2-3 GB                   │
│  Free space: ~797 GB                    │
└─────────────────────────────────────────┘
```

**Think of the NFS server as:** A shared hard drive on the network that already has the AI model files you need.

---

### What is a PersistentVolume (PV)?

A **PV** is a Kubernetes object that says:

> "I know where a storage server is, and here's how to connect to it!"

```
┌─────────────────────────────────────────┐
│  PersistentVolume (PV)                  │
│  ──────────────────────                 │
│  Name: huggingface-models-pv            │  ← YOU choose this name
│                                         │
│  What it contains:                      │
│  • NFS Server IP: 10.100.50.20         │  ← Where to connect
│  • NFS Path: /exports/huggingface-...  │  ← Which folder
│  • Size: 10Gi                           │  ← How much to use
│  • Access: ReadWriteMany                │  ← Multiple pods can use
│                                         │
│  Think of it as: A GPS coordinate       │
│  pointing to the storage server         │
└─────────────────────────────────────────┘
```

**Real-world analogy:**

The NFS server is like a **warehouse** full of goods (AI models).

The PV is like a **warehouse address card** that tells delivery trucks (Kubernetes) where the warehouse is located.

---

### How Does It Connect to Your Project?

Here's the complete flow:

```
┌─────────────────────────────────────────────────────────────────┐
│                    COMPLETE CONNECTION FLOW                     │
└─────────────────────────────────────────────────────────────────┘

Step 1: NFS Server Exists (Your team set this up)
═══════════════════════════════════════════════════
┌──────────────────────────┐
│  NFS Server              │
│  IP: 10.100.50.20        │  ← Real computer with hard drives
│  Path: /exports/...      │  ← Folder with AI models
└──────────────────────────┘
           ↑
           │ Network connection (NFS protocol)
           │


Step 2: You Create PV (Tells Kubernetes about the NFS)
═══════════════════════════════════════════════════════
You create a YAML file (01-pv-huggingface-models.yaml):

apiVersion: v1
kind: PersistentVolume
metadata:
  name: huggingface-models-pv
spec:
  capacity:
    storage: 10Gi
  nfs:
    server: 10.100.50.20           ← Points to NFS server
    path: /exports/huggingface-models  ← Points to folder

When you run: oc apply -f 01-pv-huggingface-models.yaml

Kubernetes creates:
┌──────────────────────────┐
│  PersistentVolume        │
│  Name: huggingface-      │  ← Registered in Kubernetes
│        models-pv         │
│  Status: Available       │  ← Ready to be used
└──────────────────────────┘
           ↑
           │ "I know how to connect to NFS server!"
           │


Step 3: You Create PVC (Claims the PV for Your Use)
═══════════════════════════════════════════════════════
You create another YAML file (02-pvc-huggingface-models.yaml):

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: huggingface-models-pvc
spec:
  volumeName: huggingface-models-pv  ← Points to the PV above

When you run: oc apply -f 02-pvc-huggingface-models.yaml

Kubernetes binds them:
┌──────────────────────────┐
│  PersistentVolumeClaim   │
│  Name: huggingface-      │  ← Your "reservation"
│        models-pvc        │
│  Status: Bound           │  ← Locked to the PV
│  BoundTo: huggingface-   │
│           models-pv      │
└──────────────────────────┘
           ↑
           │ "I've reserved that PV for my use!"
           │


Step 4: Your Pods Use the PVC
═══════════════════════════════════════════════════════

In your model server YAML files (06-inference-model-server.yaml):

volumes:
  - name: model-cache
    persistentVolumeClaim:
      claimName: huggingface-models-pvc  ← Reference the PVC

volumeMounts:
  - name: model-cache
    mountPath: /app/.cache/huggingface  ← Where to mount in container

When pod starts:
┌──────────────────────────────────────┐
│  Pod: inference-model-server-xxx     │
│  ────────────────────────────         │
│  Container filesystem:                │
│                                       │
│  /app/                                │
│  └── .cache/                          │
│      └── huggingface/  ← MOUNTED!    │
│          ├── models--nomic-ai--...    │  ← From NFS!
│          ├── models--mixedbread-...   │  ← From NFS!
│          └── models--onyx-dot-app--...│  ← From NFS!
│                                       │
│  The app can now read these files!    │
└──────────────────────────────────────┘
```

---

## 🔗 Visual Connection Chain

```
📦 PHYSICAL STORAGE (Infrastructure Team)
   └─ NFS Server at IP 10.100.50.20
      └─ Folder: /exports/huggingface-models
         └─ Files: AI models (2-3GB)

         ↓ (you register it)

📋 KUBERNETES REGISTRATION (You Create)
   └─ PersistentVolume (PV)
      └─ Name: huggingface-models-pv
         └─ Points to: server=10.100.50.20, path=/exports/...

         ↓ (you claim it)

🎫 KUBERNETES CLAIM (You Create)
   └─ PersistentVolumeClaim (PVC)
      └─ Name: huggingface-models-pvc
         └─ BoundTo: huggingface-models-pv

         ↓ (pods use it)

🚀 YOUR APPLICATION (Pods)
   └─ inference-model-server pod
      └─ Mounts: huggingface-models-pvc
         └─ At: /app/.cache/huggingface
            └─ Can read: All the AI model files!
```

---

## 💡 Real-World Analogy

### The Library Analogy

**NFS Server = Public Library**
- Has books (AI models)
- Located at an address (IP: 10.100.50.20)
- Has a specific section (path: /exports/huggingface-models)

**PersistentVolume (PV) = Library Card Catalog**
- You create an entry in the catalog that says:
  - "There's a library at 10.100.50.20"
  - "Go to the AI Models section"
  - "It has 10GB of books available"

**PersistentVolumeClaim (PVC) = Your Library Membership**
- You create a membership that says:
  - "I want to use that library (PV)"
  - "Reserve those books for me"

**Your Pods = Students**
- Students (pods) use your library membership (PVC)
- They can access the books (AI models)
- Multiple students can read the same books (ReadWriteMany)

---

## 🔍 The Key Questions Answered

### Q1: What is the PV?

**A:** A PV is a Kubernetes configuration file that tells Kubernetes:
- "There's an NFS server at this IP address"
- "Here's the folder path on that server"
- "Here's how much storage we want to use from it"

### Q2: Why do you need to create it?

**A:** Kubernetes doesn't automatically know about your NFS server. You need to tell Kubernetes:
- Where the NFS server is (IP address)
- What folder to use (path)
- How to connect to it (NFS version, mount options)

### Q3: What are the IP and path?

**A:** These come from your infrastructure team:

**IP Address:** The network address of the NFS server
- Example: `10.100.50.20`
- This is like `192.168.1.100` - a network address
- Your team will give you this

**Path:** The directory on that NFS server where files are stored
- Example: `/exports/huggingface-models`
- This is like `C:\Users\Documents\` on Windows
- Your team will give you this too

### Q4: How does it link to your project?

**A:** Three steps:

1. **PV points to NFS** - "Storage is at IP 10.100.50.20"
2. **PVC claims the PV** - "I want to use that storage"
3. **Pods mount the PVC** - "Give me access to those files"

Your model server pods will then have the AI model files available at `/app/.cache/huggingface/` inside the container!

---

## 📝 What You Actually Do

### Step 1: Get Information from Your Colleague

Ask them:
- **"What is the NFS server IP address for the Dev cluster?"**
  - Answer example: `10.100.50.20`
  
- **"What is the NFS export path where the models are stored?"**
  - Answer example: `/exports/huggingface-models`

### Step 2: Edit the PV YAML File

Open `01-pv-huggingface-models.yaml` and change these two lines:

```yaml
# Line 54: Change this to the IP your colleague gives you
server: 10.100.50.20  # ← CHANGE THIS!

# Line 68: Change this to the path your colleague gives you
path: "/exports/huggingface-models"  # ← CHANGE THIS!
```

### Step 3: Create the PV in Kubernetes

```bash
oc apply -f 01-pv-huggingface-models.yaml
```

**What this does:**
- Registers the NFS server in Kubernetes
- Creates a PV object
- Kubernetes now knows "there's storage available at that IP"

### Step 4: Create the PVC

```bash
oc apply -f 02-pvc-huggingface-models.yaml
```

**What this does:**
- Claims/reserves the PV for your use
- Binds the PVC to the PV
- Creates `huggingface-models-pvc` that your pods will use

### Step 5: Your Pods Automatically Use It

Your model server YAML files already have this:

```yaml
volumes:
  - name: model-cache
    persistentVolumeClaim:
      claimName: huggingface-models-pvc  # ← References the PVC
```

When the pod starts, Kubernetes:
1. Sees the pod wants `huggingface-models-pvc`
2. Looks up the PVC
3. Finds it's bound to `huggingface-models-pv`
4. Reads the PV to get NFS details (IP and path)
5. Mounts the NFS folder into the pod at `/app/.cache/huggingface/`

**The pod can now read the AI model files!**

---

## 🎨 Visual Diagram

```
┌═══════════════════════════════════════════════════════════════════┐
║                   THE COMPLETE PICTURE                            ║
╚═══════════════════════════════════════════════════════════════════╝


PHYSICAL WORLD (Outside Kubernetes):
═════════════════════════════════════

┌──────────────────────────────────┐
│  🖥️  NFS Server                  │
│  ──────────────                  │
│  IP: 10.100.50.20                │  ← A real computer
│  Physical Disk: 800 GB           │  ← Actual hard drives
│                                  │
│  Shared Folder:                  │
│  /exports/huggingface-models/    │  ← Directory accessible over network
│    ├── model files (2GB)         │  ← AI model files stored here
│    └── ...                       │
│                                  │
│  Network: Accessible by cluster  │  ← Your cluster can reach this IP
└──────────────────────────────────┘


KUBERNETES WORLD (Your Cluster):
═════════════════════════════════

Step 1: YOU CREATE PV (Tells K8s about NFS)
┌──────────────────────────────────┐
│  📄 PersistentVolume (PV)        │
│  ─────────────────────           │
│  Name: huggingface-models-pv     │  ← YOU choose this name
│  Type: NFS                       │  ← It's an NFS mount
│  Capacity: 10Gi                  │  ← We'll use 10GB (from 800GB)
│                                  │
│  Connection details:             │
│  nfs:                            │
│    server: 10.100.50.20          │  ← Points to NFS server
│    path: /exports/huggingface... │  ← Points to folder
│                                  │
│  Status: Available               │  ← Ready to be claimed
│                                  │
│  Think of it as:                 │
│  "A registration card that       │
│   knows where the NFS is"        │
└──────────────────────────────────┘
            ↓
            ↓ (Binding)
            ↓
Step 2: YOU CREATE PVC (Claims the PV)
┌──────────────────────────────────┐
│  🎫 PersistentVolumeClaim (PVC)  │
│  ───────────────────────────     │
│  Name: huggingface-models-pvc    │  ← YOU choose this name
│  Request: 10Gi                   │  ← How much storage we want
│  BoundTo: huggingface-models-pv  │  ← Locked to the PV
│                                  │
│  Status: Bound                   │  ← Successfully claimed
│                                  │
│  Think of it as:                 │
│  "A reservation ticket that      │
│   gives you access to storage"   │
└──────────────────────────────────┘
            ↓
            ↓ (Used by pods)
            ↓
Step 3: PODS USE THE PVC (Automatically)
┌──────────────────────────────────────────────────────┐
│  🚀 Pod: inference-model-server-abc123               │
│  ──────────────────────────────────                  │
│                                                      │
│  Volumes defined in YAML:                            │
│  volumes:                                            │
│    - name: model-cache                               │
│      persistentVolumeClaim:                          │
│        claimName: huggingface-models-pvc  ← Uses PVC│
│                                                      │
│  volumeMounts:                                       │
│    - name: model-cache                               │
│      mountPath: /app/.cache/huggingface  ← Where    │
│                                                      │
│  What happens when pod starts:                       │
│  1. Kubernetes sees "needs huggingface-models-pvc"   │
│  2. Looks up PVC → finds it's bound to PV           │
│  3. Reads PV → gets NFS IP and path                 │
│  4. Mounts NFS at /app/.cache/huggingface           │
│  5. Pod can now access the AI model files! ✅        │
│                                                      │
│  Inside the container:                               │
│  $ ls /app/.cache/huggingface/                       │
│  models--nomic-ai--nomic-embed-text-v1/              │
│  models--mixedbread-ai--mxbai-rerank-xsmall-v1/      │
│  models--onyx-dot-app--hybrid-intent-...             │
│                                                      │
│  The Python app loads models from here! 🎉          │
└──────────────────────────────────────────────────────┘
```

---

## 🔍 The Three-Level Connection

Think of it like a **forwarding chain**:

```
Level 1: Physical Storage (NFS Server)
└─ Real hard drives with files
   └─ IP: 10.100.50.20
      └─ Path: /exports/huggingface-models

         ↓ (PV points to this)

Level 2: Kubernetes Storage Registration (PV)
└─ Kubernetes object that knows about the NFS
   └─ Name: huggingface-models-pv
      └─ Contains: NFS IP and path

         ↓ (PVC claims this)

Level 3: Kubernetes Storage Claim (PVC)
└─ Reservation for your namespace
   └─ Name: huggingface-models-pvc
      └─ Bound to: huggingface-models-pv

         ↓ (Pods reference this)

Level 4: Your Application (Pods)
└─ Model server pods
   └─ Mount: huggingface-models-pvc
      └─ At: /app/.cache/huggingface
         └─ Access: AI model files ✅
```

---

## ❓ Common Questions

### Q: Why can't the pod just connect to NFS directly?

**A:** You COULD, but PV/PVC is better because:
- ✅ **Abstraction:** Pods don't need to know NFS details (just PVC name)
- ✅ **Portability:** Change storage backend without changing pod specs
- ✅ **Security:** NFS credentials/details centralized in PV
- ✅ **Management:** Easier to track who's using what storage

### Q: Why two files (PV and PVC)?

**A:** Separation of roles:
- **PV** = Admin/infrastructure concern (where is storage?)
- **PVC** = Developer concern (I need storage!)

This separation lets infrastructure teams manage storage separately from app teams.

### Q: What happens when I create the PV?

**A:** Kubernetes registers it:
```bash
oc apply -f 01-pv-huggingface-models.yaml
# Kubernetes: "OK, I now know about an NFS server at 10.100.50.20"
# Status: PV created, STATUS = Available (waiting to be claimed)
```

### Q: What happens when I create the PVC?

**A:** Kubernetes binds it to the PV:
```bash
oc apply -f 02-pvc-huggingface-models.yaml
# Kubernetes: "You want storage? Let me bind you to that PV!"
# Status: PVC created, STATUS = Bound (locked to the PV)
```

### Q: When do pods actually mount the NFS?

**A:** When they start:
```bash
oc apply -f 06-inference-model-server.yaml
# Kubernetes: "This pod needs huggingface-models-pvc"
# Kubernetes: "That PVC is bound to huggingface-models-pv"
# Kubernetes: "That PV points to NFS at 10.100.50.20:/exports/..."
# Kubernetes: "Let me mount that NFS into the pod!"
# Pod starts with NFS mounted at /app/.cache/huggingface/
```

---

## 📋 Simple Checklist

### Before Creating PV

- [ ] Ask colleague: "What is the Dev NFS server IP?" → `___________`
- [ ] Ask colleague: "What is the NFS export path?" → `___________`
- [ ] Ask colleague: "Is it NFSv3 or NFSv4?" → `___________`

### Create PV

- [ ] Edit `01-pv-huggingface-models.yaml`
- [ ] Change line 54: `server: YOUR_NFS_IP`
- [ ] Change line 68: `path: YOUR_NFS_PATH`
- [ ] Run: `oc apply -f 01-pv-huggingface-models.yaml`
- [ ] Verify: `oc get pv huggingface-models-pv` shows "Available"

### Create PVC

- [ ] Run: `oc apply -f 02-pvc-huggingface-models.yaml`
- [ ] Verify: `oc get pvc huggingface-models-pvc` shows "Bound"

### Test It Works

- [ ] Create test pod with PVC mounted
- [ ] Check if you can see model files
- [ ] Delete test pod

### Deploy Model Servers

- [ ] Deploy: `oc apply -f ../06-inference-model-server.yaml`
- [ ] Deploy: `oc apply -f ../06-indexing-model-server.yaml`
- [ ] Verify: Pods can read models from NFS

---

## 🎯 The Bottom Line

**Your colleague is asking you to create a PV because:**

1. They have an NFS server with AI models (800GB capacity)
2. Kubernetes doesn't know about it yet
3. You need to create a PV to register it in Kubernetes
4. Then create a PVC to claim/use it
5. Then your pods can access the models

**The PV is like a business card that says:**
> "I'm storage! You can find me at IP 10.100.50.20, folder /exports/huggingface-models"

**Your pods will use this to access the AI model files they need to run!**

---

---

## 🎫 What is a PVC? - Deep Dive

Now let's understand **PersistentVolumeClaim (PVC)** in detail.

### The Simple Definition

A **PersistentVolumeClaim (PVC)** is like a **"reservation ticket"** that says:

> "I want to use that storage! Reserve it for me!"

**Think of it like:**
- **Claiming a parking spot** - The PV is the parking garage, the PVC is your reserved spot
- **Hotel reservation** - The PV is the hotel, the PVC is your room booking
- **Library membership** - The PV is the library, the PVC is your membership card

### PV vs PVC - What's the Difference?

```
┌─────────────────────────────────────────────────────────────────┐
│                    PV vs PVC COMPARISON                         │
└─────────────────────────────────────────────────────────────────┘

PersistentVolume (PV):
━━━━━━━━━━━━━━━━━━━━━━
• Created by: Cluster admin (you, in this case)
• Scope: Cluster-wide (not in any namespace)
• Purpose: Represents physical storage
• Contains: NFS IP, path, size, access mode
• Status: Available → Bound → Released
• Think of it as: "The storage itself"

Example:
--------
apiVersion: v1
kind: PersistentVolume
metadata:
  name: huggingface-models-pv  # ← Cluster-wide name
spec:
  capacity:
    storage: 10Gi  # ← Total available
  nfs:
    server: 10.100.50.20  # ← Physical location
    path: /exports/huggingface-models


PersistentVolumeClaim (PVC):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Created by: Application deployer (you)
• Scope: Namespaced (belongs to your namespace)
• Purpose: Request/claim storage
• Contains: How much storage, which PV to bind to
• Status: Pending → Bound
• Think of it as: "A request for storage"

Example:
--------
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: huggingface-models-pvc  # ← Namespaced name
spec:
  resources:
    requests:
      storage: 10Gi  # ← How much I want
  volumeName: huggingface-models-pv  # ← Which PV to bind
```

---

## 🏗️ Detailed Architecture Diagram

### Complete System Architecture with Storage

```
╔═══════════════════════════════════════════════════════════════════════════╗
║              COMPLETE STORAGE ARCHITECTURE - DETAILED VIEW                ║
╚═══════════════════════════════════════════════════════════════════════════╝


┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  LAYER 1: PHYSICAL INFRASTRUCTURE (Your Team's Setup)                  ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

┌──────────────────────────────────────────────────────────────────────┐
│  🖥️  NFS Server (Dev Environment)                                    │
│  ════════════════════════════════════                                │
│                                                                      │
│  Hardware Details:                                                   │
│  ├─ Physical Server: nfs-server-dev.company.com                     │
│  ├─ IP Address: 10.100.50.20                                        │
│  ├─ Operating System: Linux (RHEL/Ubuntu/etc.)                      │
│  ├─ NFS Service: Running on port 2049                               │
│  └─ Total Disk Space: 800 GB                                        │
│                                                                      │
│  NFS Export Configuration:                                           │
│  ├─ Exported Path: /exports/huggingface-models                      │
│  ├─ Access: Read/Write                                              │
│  ├─ Allowed Clients: 10.0.0.0/8 (your cluster's network)            │
│  └─ NFS Version: NFSv4.1                                             │
│                                                                      │
│  Directory Structure:                                                │
│  📁 /exports/huggingface-models/                                     │
│     ├── 📁 models--nomic-ai--nomic-embed-text-v1/                   │
│     │   ├── snapshots/                                              │
│     │   │   └── abc123/                                             │
│     │   │       ├── config.json                                     │
│     │   │       ├── model.safetensors (1.2GB)                       │
│     │   │       ├── tokenizer_config.json                           │
│     │   │       └── ...                                             │
│     │   └── refs/                                                   │
│     │       └── main → abc123                                       │
│     │                                                                │
│     ├── 📁 models--mixedbread-ai--mxbai-rerank-xsmall-v1/          │
│     │   └── snapshots/...  (180MB)                                  │
│     │                                                                │
│     ├── 📁 models--onyx-dot-app--hybrid-intent-token-classifier/   │
│     │   └── snapshots/...  (95MB)                                   │
│     │                                                                │
│     └── 📁 models--onyx-dot-app--information-content-model/        │
│         └── snapshots/...  (95MB)                                   │
│                                                                      │
│  Storage Usage:                                                      │
│  ├─ Models: ~5-6 GB                                                 │
│  ├─ Free: ~794 GB                                                   │
│  └─ Total: 800 GB                                                   │
│                                                                      │
│  Network Accessibility:                                              │
│  ✅ Accessible from OpenShift cluster nodes                         │
│  ✅ Firewall rules allow NFS traffic (port 2049)                    │
│  ✅ Cluster nodes can ping 10.100.50.20                             │
└──────────────────────────────────────────────────────────────────────┘
                                ↑
                                │
                                │ Network (NFS protocol over TCP/IP)
                                │
                                ↓

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  LAYER 2: KUBERNETES STORAGE ABSTRACTION (You Create)                  ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Step 2a: Create PersistentVolume (PV)
┌──────────────────────────────────────────────────────────────────────┐
│  📄 PersistentVolume: huggingface-models-pv                          │
│  ═══════════════════════════════════════════                         │
│                                                                      │
│  Metadata:                                                           │
│  ├─ Name: huggingface-models-pv                                     │
│  ├─ Labels:                                                          │
│  │   ├─ type: nfs                                                    │
│  │   ├─ app: onyx-model-servers                                     │
│  │   └─ environment: dev                                            │
│  └─ Created by: YOU (cluster admin)                                 │
│                                                                      │
│  Spec (Configuration):                                               │
│  ├─ Capacity:                                                        │
│  │   └─ storage: 10Gi  ← How much we're exposing to Kubernetes     │
│  │                       (from 800Gi total on NFS)                  │
│  │                                                                   │
│  ├─ Access Modes:                                                    │
│  │   └─ ReadWriteMany  ← Multiple pods can read/write              │
│  │                       (Important: both model servers can share!)  │
│  │                                                                   │
│  ├─ Reclaim Policy:                                                  │
│  │   └─ Retain  ← Keep data when PVC deleted (SAFE!)               │
│  │                                                                   │
│  ├─ Storage Class:                                                   │
│  │   └─ "" (empty)  ← Static provisioning (manual binding)         │
│  │                                                                   │
│  ├─ Mount Options:                                                   │
│  │   ├─ hard        ← Retry on NFS errors                           │
│  │   ├─ nfsvers=4.1 ← NFS protocol version                          │
│  │   ├─ timeo=600   ← 60 second timeout                             │
│  │   └─ retrans=2   ← Retry 2 times                                 │
│  │                                                                   │
│  └─ NFS Configuration:                                               │
│      ├─ server: 10.100.50.20  ← NFS server IP (FROM YOUR TEAM)     │
│      └─ path: /exports/huggingface-models  ← NFS folder (FROM TEAM)│
│                                                                      │
│  Status After Creation:                                              │
│  ├─ Phase: Available  ← Ready to be claimed                         │
│  ├─ ClaimRef: None  ← Not bound to any PVC yet                      │
│  └─ Message: "PV is available for claims"                           │
│                                                                      │
│  YAML File: 01-pv-huggingface-models.yaml                           │
│  Command: oc apply -f 01-pv-huggingface-models.yaml                 │
└──────────────────────────────────────────────────────────────────────┘
                                ↓
                                │ (Binding happens when PVC is created)
                                ↓
Step 2b: Create PersistentVolumeClaim (PVC)
┌──────────────────────────────────────────────────────────────────────┐
│  🎫 PersistentVolumeClaim: huggingface-models-pvc                    │
│  ════════════════════════════════════════════════                    │
│                                                                      │
│  Metadata:                                                           │
│  ├─ Name: huggingface-models-pvc                                    │
│  ├─ Namespace: onyx-infra (or your namespace)                       │
│  ├─ Labels:                                                          │
│  │   ├─ app: onyx-model-servers                                     │
│  │   └─ component: model-cache                                      │
│  └─ Created by: YOU (application deployer)                          │
│                                                                      │
│  Spec (What you're requesting):                                      │
│  ├─ Access Modes:                                                    │
│  │   └─ ReadWriteMany  ← Must match PV's access mode               │
│  │                                                                   │
│  ├─ Storage Class:                                                   │
│  │   └─ "" (empty)  ← Must match PV (for static binding)           │
│  │                                                                   │
│  ├─ Resources:                                                       │
│  │   └─ requests:                                                    │
│  │       └─ storage: 10Gi  ← How much storage you want             │
│  │                           (must be ≤ PV capacity)                │
│  │                                                                   │
│  ├─ Volume Name:                                                     │
│  │   └─ huggingface-models-pv  ← CRITICAL: Binds to specific PV!   │
│  │                               This makes the binding explicit     │
│  │                                                                   │
│  └─ Volume Mode:                                                     │
│      └─ Filesystem  ← Use as a filesystem (not block device)        │
│                                                                      │
│  Status After Creation:                                              │
│  ├─ Phase: Bound  ← Successfully bound to PV ✅                     │
│  ├─ Volume: huggingface-models-pv  ← Which PV it's bound to        │
│  ├─ Capacity: 10Gi  ← Actual storage allocated                     │
│  └─ Access Modes: RWX  ← ReadWriteMany enabled                     │
│                                                                      │
│  What Happens During Binding:                                        │
│  1. You create PVC with volumeName pointing to PV                   │
│  2. Kubernetes finds PV with name "huggingface-models-pv"           │
│  3. Checks if PV is Available (not bound to another PVC)            │
│  4. Checks if requirements match:                                    │
│     ├─ Storage: PVC wants 10Gi, PV has 10Gi ✅                      │
│     ├─ Access mode: Both want ReadWriteMany ✅                      │
│     └─ StorageClass: Both have "" ✅                                 │
│  5. Binds PVC to PV (locks them together)                           │
│  6. Updates PV status: Available → Bound                            │
│  7. Updates PVC status: Pending → Bound                             │
│  8. PVC is now ready for pods to use! ✅                             │
│                                                                      │
│  YAML File: 02-pvc-huggingface-models.yaml                          │
│  Command: oc apply -f 02-pvc-huggingface-models.yaml                │
└──────────────────────────────────────────────────────────────────────┘
                                ↓
                                │ (Pods reference the PVC)
                                ↓

┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃  LAYER 3: APPLICATION LAYER (Your Pods Use the PVC)                    ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

Step 3: Deploy Pods with PVC
┌──────────────────────────────────────────────────────────────────────┐
│  🚀 Pod: inference-model-server-7b4f8c9d-xk2m5                       │
│  ════════════════════════════════════════════════                    │
│                                                                      │
│  Pod Spec (from 06-inference-model-server.yaml):                    │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  volumes:                                                  │    │
│  │    - name: model-cache  ← Internal name in pod             │    │
│  │      persistentVolumeClaim:                                │    │
│  │        claimName: huggingface-models-pvc  ← References PVC │    │
│  │                                                            │    │
│  │  volumeMounts:                                             │    │
│  │    - name: model-cache  ← Must match volume name above    │    │
│  │      mountPath: /app/.cache/huggingface  ← Where to mount │    │
│  │      readOnly: true  ← Don't allow writes                 │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  What Kubernetes Does When Pod Starts:                               │
│  ────────────────────────────────────────                            │
│  1. Reads pod spec → sees "need huggingface-models-pvc"             │
│  2. Looks up PVC in same namespace                                  │
│  3. Checks PVC status → Bound to "huggingface-models-pv" ✅         │
│  4. Reads PV specification → gets NFS details                       │
│  5. Contacts NFS server at 10.100.50.20                             │
│  6. Mounts /exports/huggingface-models into pod                     │
│  7. Makes it available at /app/.cache/huggingface in container      │
│  8. Pod starts successfully! ✅                                      │
│                                                                      │
│  Container Filesystem After Mount:                                   │
│  ──────────────────────────────────────                              │
│  /                                                                   │
│  ├── bin/                                                            │
│  ├── etc/                                                            │
│  ├── app/                                                            │
│  │   ├── model_server/  (Python code)                               │
│  │   └── .cache/                                                     │
│  │       └── huggingface/  ← NFS MOUNTED HERE!                     │
│  │           ├── models--nomic-ai--nomic-embed-text-v1/  ← From NFS│
│  │           ├── models--mixedbread-ai--mxbai-rerank-xsmall-v1/    │
│  │           └── models--onyx-dot-app--hybrid-intent-...            │
│  └── ...                                                             │
│                                                                      │
│  Python Code Can Now:                                                │
│  ──────────────────────                                              │
│  from transformers import AutoModel                                  │
│  model = AutoModel.from_pretrained("nomic-ai/nomic-embed-text-v1") │
│  # Loads from: /app/.cache/huggingface/models--nomic-ai--...        │
│  # No internet needed! ✅                                            │
│  # Model loaded into memory! ✅                                      │
└──────────────────────────────────────────────────────────────────────┘


┌──────────────────────────────────────────────────────────────────────┐
│  🚀 Pod: indexing-model-server-9d2c5f8a-pm7k3                        │
│  ═══════════════════════════════════════════════                     │
│                                                                      │
│  Uses THE SAME PVC! (ReadWriteMany allows sharing)                  │
│  ────────────────────────────────────────────────                    │
│  volumes:                                                            │
│    - name: indexing-model-cache                                      │
│      persistentVolumeClaim:                                          │
│        claimName: huggingface-models-pvc  ← SAME PVC!               │
│                                                                      │
│  Mounts at: /app/.cache/huggingface (read-only)                     │
│  Accesses: SAME model files from SAME NFS! ✅                        │
│                                                                      │
│  Benefits:                                                           │
│  ✅ No duplicate storage (both pods read same files)                │
│  ✅ Consistent models (both use exact same versions)                │
│  ✅ Easy updates (update NFS once, both pods get it)                │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Complete Data Flow - From NFS to Application

```
┌═══════════════════════════════════════════════════════════════════════════┐
│                        COMPLETE DATA FLOW DIAGRAM                         │
└═══════════════════════════════════════════════════════════════════════════┘


STEP 1: INFRASTRUCTURE TEAM PREPARES NFS
═════════════════════════════════════════

┌─────────────┐
│ Infra Team  │
└──────┬──────┘
       │
       │ 1. Set up NFS server at 10.100.50.20
       │ 2. Create export: /exports/huggingface-models
       │ 3. Download Hugging Face models (~5-6GB)
       │ 4. Configure NFS exports (allow cluster access)
       │ 5. Give you NFS IP and path
       │
       ↓
┌──────────────────────────┐
│  NFS Server Ready        │
│  IP: 10.100.50.20        │
│  Path: /exports/...      │
│  Models: ✅ Loaded       │
└──────────────────────────┘


STEP 2: YOU CREATE PV (Register NFS in Kubernetes)
═══════════════════════════════════════════════════

┌─────────────┐
│    You      │
└──────┬──────┘
       │
       │ 1. Get NFS IP from team: 10.100.50.20
       │ 2. Get NFS path from team: /exports/huggingface-models
       │ 3. Edit 01-pv-huggingface-models.yaml
       │ 4. Update: server: 10.100.50.20
       │ 5. Update: path: /exports/huggingface-models
       │ 6. Run: oc apply -f 01-pv-huggingface-models.yaml
       │
       ↓
┌──────────────────────────────────────────────────┐
│  Kubernetes creates PV object                    │
│  ────────────────────────────────                │
│  Name: huggingface-models-pv                     │
│  Type: NFS                                       │
│  Server: 10.100.50.20  ← Stored in Kubernetes   │
│  Path: /exports/...    ← Stored in Kubernetes   │
│  Status: Available     ← Ready to be claimed     │
└──────────────────────────────────────────────────┘
       ↓
       │ PV now exists in cluster (cluster-wide resource)
       │ You can see it: oc get pv
       │


STEP 3: YOU CREATE PVC (Claim the PV)
═══════════════════════════════════════════════════

┌─────────────┐
│    You      │
└──────┬──────┘
       │
       │ 1. Review 02-pvc-huggingface-models.yaml
       │ 2. It references volumeName: huggingface-models-pv
       │ 3. Run: oc apply -f 02-pvc-huggingface-models.yaml
       │
       ↓
┌──────────────────────────────────────────────────┐
│  Kubernetes Binding Process                      │
│  ──────────────────────────                      │
│  1. Receives PVC creation request                │
│  2. Sees: volumeName = huggingface-models-pv     │
│  3. Looks up that PV                             │
│  4. Checks PV status: Available ✅               │
│  5. Checks requirements match:                   │
│     ├─ Storage: PVC wants 10Gi, PV has 10Gi ✅  │
│     ├─ Access: Both ReadWriteMany ✅             │
│     └─ StorageClass: Both "" ✅                  │
│  6. BINDS them together! 🔗                      │
│  7. Updates PV: Available → Bound               │
│  8. Updates PVC: Pending → Bound                │
└──────────────────────────────────────────────────┘
       ↓
┌──────────────────────────────────────────────────┐
│  PVC is now Bound! ✅                            │
│  ────────────────────                            │
│  Name: huggingface-models-pvc                    │
│  Namespace: onyx-infra                           │
│  Bound to: huggingface-models-pv                 │
│  Status: Bound                                   │
│  Capacity: 10Gi                                  │
│                                                  │
│  You can now use this PVC in your pods!          │
└──────────────────────────────────────────────────┘
       ↓
       │ PVC ready for pods to reference
       │


STEP 4: PODS MOUNT THE PVC (Automatic)
═══════════════════════════════════════════════════

┌─────────────┐
│    You      │
└──────┬──────┘
       │
       │ Deploy model servers:
       │ oc apply -f 06-inference-model-server.yaml
       │ oc apply -f 06-indexing-model-server.yaml
       │
       ↓
┌──────────────────────────────────────────────────┐
│  Kubernetes Pod Scheduling & Mounting            │
│  ───────────────────────────────────────         │
│                                                  │
│  For EACH pod:                                   │
│  ────────────                                    │
│  1. Reads pod spec                               │
│  2. Sees: volumes use PVC "huggingface-models-pvc"│
│  3. Looks up PVC in same namespace               │
│  4. Checks PVC status: Bound ✅                  │
│  5. Gets bound PV: huggingface-models-pv         │
│  6. Reads PV details:                            │
│     ├─ Type: NFS                                 │
│     ├─ Server: 10.100.50.20                     │
│     ├─ Path: /exports/huggingface-models        │
│     └─ Mount options: hard, nfsvers=4.1, ...    │
│  7. Schedules pod on a node                      │
│  8. Node's kubelet mounts NFS:                   │
│     ├─ Connects to 10.100.50.20:2049            │
│     ├─ Mounts /exports/huggingface-models       │
│     └─ Makes it available to container          │
│  9. Container starts with NFS mounted            │
│ 10. Application can read model files! ✅         │
└──────────────────────────────────────────────────┘
       ↓
┌──────────────────────────────────────────────────┐
│  BOTH Pods Running with Shared Storage          │
│  ──────────────────────────────────────          │
│                                                  │
│  inference-model-server-xxx                      │
│  ├─ Reads from: /app/.cache/huggingface/        │
│  └─ Accesses: nomic-ai/nomic-embed-text-v1      │
│                                                  │
│  indexing-model-server-xxx                       │
│  ├─ Reads from: /app/.cache/huggingface/        │
│  └─ Accesses: nomic-ai/nomic-embed-text-v1      │
│                                                  │
│  Both read from SAME NFS location! ✅            │
│  No duplication! ✅                              │
└──────────────────────────────────────────────────┘


STEP 5: APPLICATION USES MODELS
═══════════════════════════════════════════════════

┌──────────────────────────────────────────────────┐
│  Inside Container (Python Application)           │
│  ────────────────────────────────────            │
│                                                  │
│  When app runs:                                  │
│  from sentence_transformers import ...           │
│  model = SentenceTransformer(                    │
│      'nomic-ai/nomic-embed-text-v1'              │
│  )                                               │
│                                                  │
│  Hugging Face library:                           │
│  1. Checks HF_HOME env var                       │
│     → /app/.cache/huggingface                    │
│  2. Looks for model in cache                     │
│     → /app/.cache/huggingface/models--nomic-ai...│
│  3. Finds model files! ✅                        │
│  4. Loads model into memory (~2GB RAM)           │
│  5. Model ready to generate embeddings! ✅       │
│                                                  │
│  All of this WITHOUT internet! ✅                │
│  Because files are on NFS! ✅                    │
└──────────────────────────────────────────────────┘
```

---

## 🎓 PVC Deep Dive - Every Field Explained

Let's look at the PVC YAML line by line:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: huggingface-models-pvc
  labels:
    app: onyx-model-servers
    component: model-cache
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  resources:
    requests:
      storage: 10Gi
  volumeName: huggingface-models-pv
  volumeMode: Filesystem
```

### Field-by-Field Explanation

#### `apiVersion: v1`
- **What:** Kubernetes API version
- **Value:** `v1` (standard for core resources)
- **Think of it as:** "I'm using the official Kubernetes API"

#### `kind: PersistentVolumeClaim`
- **What:** Type of Kubernetes resource
- **Value:** `PersistentVolumeClaim`
- **Think of it as:** "I'm creating a storage claim"

#### `metadata.name: huggingface-models-pvc`
- **What:** The name of this PVC
- **Value:** `huggingface-models-pvc`
- **Important:** Pods will reference this name!
- **Think of it as:** "My reservation number"

#### `metadata.labels`
- **What:** Tags for organizing and selecting
- **Values:**
  - `app: onyx-model-servers` - Which application
  - `component: model-cache` - What it's for
- **Think of it as:** "Category labels for finding this later"

#### `spec.accessModes: [ReadWriteMany]`
- **What:** How pods can access this storage
- **Value:** `ReadWriteMany` (RWX)
- **Meaning:**
  - **Read:** Pods can read files ✅
  - **Write:** Pods can write files (we set readOnly in pod spec)
  - **Many:** Multiple pods can mount simultaneously ✅
- **Why important:** Both model servers need to read at the same time!
- **Alternatives:**
  - `ReadWriteOnce` (RWO) - Only one pod can mount
  - `ReadOnlyMany` (ROX) - Multiple pods, read-only
- **Think of it as:** "Shared access, multiple readers allowed"

#### `spec.storageClassName: ""`
- **What:** Which StorageClass to use for dynamic provisioning
- **Value:** `""` (empty string)
- **Meaning:** Static provisioning (manual binding, no auto-creation)
- **Why empty:** We're binding to a specific PV (not auto-creating storage)
- **Think of it as:** "I'll manually choose my PV, don't auto-create"

#### `spec.resources.requests.storage: 10Gi`
- **What:** How much storage you're requesting
- **Value:** `10Gi` (10 gigabytes)
- **Important:** Must be ≤ PV's capacity
- **Why 10Gi:** Models need ~5-6GB, 10Gi gives buffer
- **Think of it as:** "I want 10GB of storage space"

#### `spec.volumeName: huggingface-models-pv`
- **What:** Explicit binding to a specific PV
- **Value:** `huggingface-models-pv` (the PV we created)
- **Critical:** This makes the binding explicit (not automatic)
- **Why needed:** Ensures PVC binds to OUR PV (not some other PV)
- **Think of it as:** "I specifically want THAT parking spot"

#### `spec.volumeMode: Filesystem`
- **What:** How to present the storage
- **Value:** `Filesystem`
- **Meaning:** Mount as a directory tree (normal files/folders)
- **Alternative:** `Block` (raw block device)
- **Think of it as:** "Give me folders and files, not raw disk"

---

## 🌐 Network Flow Diagram

```
┌═══════════════════════════════════════════════════════════════════════════┐
│              NETWORK COMMUNICATION FLOW (DETAILED)                        │
└═══════════════════════════════════════════════════════════════════════════┘


Physical Network:
═════════════════

┌─────────────────┐                           ┌─────────────────┐
│  NFS Server     │                           │ OpenShift Node  │
│  10.100.50.20   │◄──────────────────────────│ 10.0.1.50       │
│                 │  NFS Protocol (TCP 2049)  │                 │
│  /exports/      │                           │  Kubelet runs   │
│  huggingface-   │                           │  here           │
│  models/        │                           │                 │
└─────────────────┘                           └─────────────────┘
       │                                              │
       │ Data stored here                            │ Mounts NFS here
       │ (AI models)                                  │
       │                                              │
       │                                              ↓
       │                              ┌───────────────────────────┐
       │                              │  Pod Container            │
       │                              │  /app/.cache/huggingface/ │
       │                              │  (NFS mounted here)       │
       │                              └───────────────────────────┘
       │                                              │
       │                                              │
       └──────────────────────────────────────────────┘
         Models are accessible in container via network mount!


Kubernetes Abstraction Layers:
═══════════════════════════════

┌──────────────┐      ┌──────────────┐      ┌──────────────┐
│  NFS Server  │ ───► │      PV      │ ───► │     PVC      │ ───► │  Pod  │
│  (Physical)  │      │ (K8s Object) │      │ (K8s Object) │      │       │
└──────────────┘      └──────────────┘      └──────────────┘      └───────┘
  Real storage        Registration          Reservation          Usage

  Team manages        You create            You create          You deploy
  NFS server          PV definition         PVC definition      Pods

  Contains:           Contains:             Contains:           Contains:
  • Actual files      • NFS IP             • PV reference      • PVC reference
  • 800GB disk        • NFS path           • Storage request   • Mount path
  • Network addr      • Capacity 10Gi      • Bound to PV       • App code


Data Flow (When Pod Reads a File):
═══════════════════════════════════

Pod: model-server
    ↓
    │ Python code: model = SentenceTransformer('nomic-ai/...')
    ↓
Container Filesystem
    ↓
    │ Accesses: /app/.cache/huggingface/models--nomic-ai.../model.safetensors
    ↓
Volume Mount (model-cache)
    ↓
    │ Mounted from: PVC huggingface-models-pvc
    ↓
PVC (huggingface-models-pvc)
    ↓
    │ Bound to: PV huggingface-models-pv
    ↓
PV (huggingface-models-pv)
    ↓
    │ Points to: NFS 10.100.50.20:/exports/huggingface-models
    ↓
NFS Client (on OpenShift node)
    ↓
    │ Network request to: 10.100.50.20:2049
    ↓
NFS Server
    ↓
    │ Returns: File data from /exports/huggingface-models/...
    ↓
Data flows back through chain to Pod
    ↓
Python app receives model file and loads it! ✅
```

---

## 🔐 Security & Access Control

```
┌═══════════════════════════════════════════════════════════════════════════┐
│                    ACCESS CONTROL & PERMISSIONS                           │
└═══════════════════════════════════════════════════════════════════════════┘


Layer 1: Network Level (Firewall)
═══════════════════════════════════

NFS Server: 10.100.50.20
├─ Firewall allows: 10.0.0.0/8 (cluster network)
├─ Port: 2049 (NFS) open for cluster
└─ Other IPs: Blocked


Layer 2: NFS Export Level
═══════════════════════════

NFS Export: /exports/huggingface-models
├─ Allowed clients: 10.0.0.0/8 (cluster subnet)
├─ Access: Read/Write (rw)
├─ Root squash: no_root_squash or root_squash
└─ Example export line:
    /exports/huggingface-models 10.0.0.0/8(rw,sync,no_root_squash)


Layer 3: File System Permissions
═══════════════════════════════════

Files on NFS:
├─ Owner: root (or nfsnobody)
├─ Group: root (or nfsnobody)
├─ Permissions: 755 (rwxr-xr-x)
└─ All users can read: ✅


Layer 4: Kubernetes RBAC
═══════════════════════════

PV Creation:
├─ Requires: cluster-admin or persistent-volumes permissions
└─ You need: oc adm policy add-role-to-user cluster-admin <user>

PVC Creation:
├─ Requires: Standard user permissions in namespace
└─ You need: Access to your namespace


Layer 5: Pod Security
═══════════════════════

volumeMounts:
├─ readOnly: true  ← Pod can only read, not write
├─ Security Context: May need specific UID/GID
└─ OpenShift SCC: May need anyuid or hostmount-anyuid


Complete Access Path:
═════════════════════

Request from Pod
    ↓ (checks namespace permissions)
Access PVC "huggingface-models-pvc"
    ↓ (checks if bound)
Access PV "huggingface-models-pv"
    ↓ (checks cluster permissions)
Mount NFS 10.100.50.20:/exports/...
    ↓ (checks NFS export rules)
Access file on NFS server
    ↓ (checks file permissions)
Read model file
    ↓
Return data to pod ✅
```

---

## 📊 Resource Lifecycle

```
┌═══════════════════════════════════════════════════════════════════════════┐
│                    PV AND PVC LIFECYCLE STATES                            │
└═══════════════════════════════════════════════════════════════════════════┘


PersistentVolume (PV) States:
═══════════════════════════════

Available
    ↓
    │ PV created, waiting for a PVC to claim it
    │ Command: oc get pv → STATUS: Available
    │
Bound
    ↓
    │ PVC has claimed this PV
    │ Command: oc get pv → STATUS: Bound
    │ CLAIM: namespace/pvc-name
    │
Released (if PVC deleted with Retain policy)
    ↓
    │ PVC deleted but data retained
    │ PV needs manual cleanup to be reused
    │
Failed
    ↓
    │ Error occurred (rare)
    │


PersistentVolumeClaim (PVC) States:
═════════════════════════════════════

Pending
    ↓
    │ PVC created, looking for suitable PV
    │ Command: oc get pvc → STATUS: Pending
    │ Waiting for: PV with matching requirements
    │
Bound
    ↓
    │ Successfully bound to a PV
    │ Command: oc get pvc → STATUS: Bound
    │ VOLUME: pv-name
    │ Pods can now use this PVC ✅
    │
Lost (if PV deleted while PVC exists)
    ↓
    │ PV disappeared, PVC orphaned
    │


Timeline Example:
═════════════════

00:00 │ You create PV
      │ oc apply -f 01-pv-huggingface-models.yaml
      │ PV Status: Available
      │
00:05 │ You create PVC
      │ oc apply -f 02-pvc-huggingface-models.yaml
      │ PVC Status: Pending (for 1-2 seconds)
      │
00:07 │ Kubernetes binds them
      │ PV Status: Available → Bound
      │ PVC Status: Pending → Bound
      │ Binding complete! ✅
      │
00:10 │ You deploy pod
      │ oc apply -f 06-inference-model-server.yaml
      │ Pod Status: Pending → ContainerCreating
      │
00:15 │ Node mounts NFS
      │ Node contacts 10.100.50.20
      │ Mounts /exports/huggingface-models
      │ Pod Status: ContainerCreating → Running
      │
00:20 │ Pod loads models
      │ Python app reads from /app/.cache/huggingface/
      │ Models loaded into memory
      │ Pod ready! ✅
```

---

## 🔍 Troubleshooting with Commands

### Check PV Status

```bash
# List all PVs in cluster
oc get pv

# Expected output:
# NAME                     CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM
# huggingface-models-pv    10Gi       RWX            Retain           Available

# After PVC created:
# huggingface-models-pv    10Gi       RWX            Retain           Bound       onyx-infra/huggingface-models-pvc

# Detailed info
oc describe pv huggingface-models-pv

# Shows:
# - NFS server IP
# - NFS path
# - Which PVC claimed it
# - Events and status changes
```

### Check PVC Status

```bash
# List PVCs in your namespace
oc get pvc

# Expected output:
# NAME                        STATUS   VOLUME                    CAPACITY   ACCESS MODES
# huggingface-models-pvc      Bound    huggingface-models-pv     10Gi       RWX

# Detailed info
oc describe pvc huggingface-models-pvc

# Shows:
# - Which PV it's bound to
# - Requested vs allocated storage
# - Access modes
# - Events (why it's pending, errors, etc.)
```

### Check if NFS is Actually Mounted in Pod

```bash
# Get pod name
POD_NAME=$(oc get pods -l app=inference-model-server -o jsonpath='{.items[0].metadata.name}')

# Check mounts inside pod
oc exec $POD_NAME -- df -h | grep huggingface

# Expected output:
# 10.100.50.20:/exports/huggingface-models  800G  6.0G  794G   1% /app/.cache/huggingface

# List model files
oc exec $POD_NAME -- ls -lh /app/.cache/huggingface/

# Should show:
# models--nomic-ai--nomic-embed-text-v1/
# models--mixedbread-ai--mxbai-rerank-xsmall-v1/
# ...

# Check if models can be loaded
oc logs $POD_NAME | grep -i "loaded model"

# Should see:
# "Loaded model from local cache: /app/.cache/huggingface/models--nomic-ai..."
```

### Debug NFS Connection

```bash
# Create debug pod to test NFS
cat > debug-nfs.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: debug-nfs
spec:
  containers:
    - name: debug
      image: registry.access.redhat.com/ubi8/ubi:latest
      command: ["sleep", "3600"]
      volumeMounts:
        - name: nfs-test
          mountPath: /mnt/nfs
  volumes:
    - name: nfs-test
      persistentVolumeClaim:
        claimName: huggingface-models-pvc
EOF

oc apply -f debug-nfs.yaml
oc wait --for=condition=Ready pod/debug-nfs --timeout=60s

# Test access
oc exec debug-nfs -- ls -lh /mnt/nfs/
oc exec debug-nfs -- df -h /mnt/nfs/

# If it works, your NFS setup is correct! ✅

# Clean up
oc delete pod debug-nfs
```

---

## 📋 Complete YAML Reference

### PV YAML Structure

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: <pv-name>                    # Cluster-wide unique name
  labels:                            # Optional tags
    key: value
spec:
  capacity:
    storage: <size>                  # e.g., 10Gi, 100Gi
  accessModes:                       # How pods can access
    - ReadWriteMany                  # Multiple pods, read/write
    # OR ReadWriteOnce                # Single pod only
    # OR ReadOnlyMany                 # Multiple pods, read-only
  persistentVolumeReclaimPolicy:     # What happens when PVC deleted
    Retain                           # Keep data (recommended)
    # OR Delete                       # Delete data (dangerous!)
  storageClassName: ""               # Empty for static binding
  mountOptions:                      # NFS-specific options
    - hard                           # Keep trying on errors
    - nfsvers=4.1                    # NFS version
    - timeo=600                      # Timeout (deciseconds)
  nfs:                               # NFS configuration
    server: <ip-address>             # NFS server IP
    path: <export-path>              # NFS export path
```

### PVC YAML Structure

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <pvc-name>                   # Namespaced name
  namespace: <your-namespace>        # Optional (uses current)
  labels:                            # Optional tags
    key: value
spec:
  accessModes:                       # Must match PV
    - ReadWriteMany
  storageClassName: ""               # Must match PV
  resources:
    requests:
      storage: <size>                # Must be ≤ PV capacity
  volumeName: <pv-name>              # Explicit PV binding
  volumeMode: Filesystem             # Filesystem (not Block)
```

### Pod Volume Mount Structure

```yaml
# In pod spec
spec:
  containers:
    - name: <container-name>
      volumeMounts:
        - name: <volume-name>        # Internal reference
          mountPath: <path-in-container>  # Where to mount
          readOnly: true             # Optional: read-only
  volumes:
    - name: <volume-name>            # Must match volumeMount
      persistentVolumeClaim:
        claimName: <pvc-name>        # PVC to use
```

---

## 🎯 Summary Comparison Table

| Aspect | PersistentVolume (PV) | PersistentVolumeClaim (PVC) |
|--------|----------------------|----------------------------|
| **Scope** | Cluster-wide | Namespaced |
| **Who creates** | Cluster admin (you) | App deployer (you) |
| **Purpose** | Represent physical storage | Request storage |
| **Contains** | NFS IP, path, capacity | Storage request, PV reference |
| **Lifecycle** | Independent of namespace | Tied to namespace |
| **Name** | huggingface-models-pv | huggingface-models-pvc |
| **References** | NFS server | PV name |
| **Used by** | PVC (via binding) | Pods (via claimName) |
| **Status** | Available/Bound/Released | Pending/Bound/Lost |
| **Can be deleted** | Yes (but may lose data!) | Yes (PV policy determines fate) |

---

## ✅ Final Checklist & Quick Commands

### Before You Start

Ask your colleague:
- [ ] Dev NFS server IP: `_______________`
- [ ] NFS export path: `_______________`
- [ ] NFS version: `_______________`
- [ ] Do I have cluster-admin permissions? `_______________`

### Create PV

```bash
# 1. Edit the file
vi 01-pv-huggingface-models.yaml
# Change: server: YOUR_IP
# Change: path: YOUR_PATH

# 2. Create PV
oc apply -f 01-pv-huggingface-models.yaml

# 3. Verify
oc get pv huggingface-models-pv
# Expected: STATUS = Available

# 4. Check details
oc describe pv huggingface-models-pv | grep -A 5 "NFS"
# Should show your IP and path
```

### Create PVC

```bash
# 1. Create PVC (no edits needed)
oc apply -f 02-pvc-huggingface-models.yaml

# 2. Verify binding
oc get pvc huggingface-models-pvc
# Expected: STATUS = Bound, VOLUME = huggingface-models-pv

# 3. Check details
oc describe pvc huggingface-models-pvc
# Should show: Successfully bound to PV
```

### Verify NFS Access

```bash
# Quick test
oc run test --image=registry.access.redhat.com/ubi8/ubi --command -- sleep 300
oc set volume pod/test --add --name=m --type=pvc --claim-name=huggingface-models-pvc --mount-path=/mnt
oc exec test -- ls -lh /mnt/
# Should show model directories
oc delete pod test
```

### Deploy Model Servers

```bash
# Deploy both servers
oc apply -f ../06-inference-model-server.yaml
oc apply -f ../06-indexing-model-server.yaml

# Check they're running
oc get pods | grep model-server

# Check they loaded models from NFS (not downloading)
oc logs deployment/inference-model-server | head -50
oc logs deployment/indexing-model-server | head -50
# Should NOT see "Downloading from huggingface.co"
# Should see "Loaded model from local cache"
```

---

**Now you have a complete, deep understanding of PV, PVC, and how they connect your project to NFS storage!** 🎉

