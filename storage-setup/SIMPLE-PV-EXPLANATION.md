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

**Now you understand what a PV is and how it connects everything!** 🎉

