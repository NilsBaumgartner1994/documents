# Paperless-ngx + Google Drive Sync + Traefik

A ready-to-run Docker Compose stack that combines:

| Component | Purpose |
|---|---|
| **[Paperless-ngx](https://docs.paperless-ngx.com/)** | Document management system (scan, OCR, tag, search) |
| **[PostgreSQL 16](https://www.postgresql.org/)** | Database for Paperless-ngx |
| **[Redis 7](https://redis.io/)** | Task queue / message broker |
| **[Gotenberg](https://gotenberg.dev/)** | Document → PDF conversion (DOCX, XLSX, …) |
| **[Apache Tika](https://tika.apache.org/)** | Content extraction for full-text search |
| **[Ollama](https://ollama.com/)** | Local LLM inference server (runs gemma4:e4b) |
| **[Open WebUI](https://openwebui.com/)** | ChatGPT-like interface for the local AI |
| **[rclone](https://rclone.org/)** | Periodic sync of documents to **Google Drive** |
| **[Traefik v3](https://traefik.io/traefik/)** | Reverse proxy with automatic **Let's Encrypt** TLS |

---

## Prerequisites

- A Linux machine (or macOS / Windows with Docker Desktop) with Docker ≥ 24 and Docker Compose v2 (`docker compose`).
- **For production:** A public domain name pointing to the server's IP, ports **80** and **443** open.
- **Optional:** A Google account (for Google Drive sync).

---

## Quick-start

### 1 – Clone & copy environment file

```bash
git clone https://github.com/NilsBaumgartner1994/documents.git
cd documents
cp .env.example .env
```

### 2 – Edit `.env`

Open `.env` and fill in **at least** the required values:

```dotenv
PAPERLESS_SECRET_KEY=<random 64-char string>
PAPERLESS_DBPASS=<strong password>
```

The defaults are set for **local use** (`localhost` / `ai.localhost`).
For production, also update:

```dotenv
PAPERLESS_DOMAIN=paperless.example.com
PAPERLESS_URL=https://paperless.example.com
OPEN_WEBUI_DOMAIN=ai.paperless.example.com
OPEN_WEBUI_AUTH=true
ACME_EMAIL=your-email@example.com          # required for Let's Encrypt
```

Generate a secure secret key:

```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

### 3 – Create the Traefik certificate store

Traefik stores TLS private keys in `traefik/acme.json`.
The file **must** be owned by the process user and have permissions `600`:

```bash
touch traefik/acme.json
chmod 600 traefik/acme.json
```

### 4 – Configure rclone for Google Drive

> **Skip this step if you don't need Google Drive sync.**
> You can disable the `rclone-sync` service by commenting it out in
> `docker-compose.yml`.

#### Option A – OAuth (personal Google account, recommended)

First, **install rclone on your local machine** (not the server):
[https://rclone.org/install/](https://rclone.org/install/)

Then run `rclone config` and follow the interactive wizard to create a remote
named `gdrive` with `drive` scope.  Copy the resulting token to the server:

```bash
# On your local machine:
rclone config   # create remote named "gdrive", type "drive"
# After completing the OAuth flow, copy the token value:
cat ~/.config/rclone/rclone.conf   # look for the "token = …" line under [gdrive]

# On the server – paste the token value into .env:
# RCLONE_TOKEN={"access_token":"…","refresh_token":"…",…}
```

#### Option B – Service account (Google Workspace / automated setups)

1. Create a service account in [Google Cloud Console](https://console.cloud.google.com/iam-admin/serviceaccounts).
2. Grant it "Editor" access to the target Google Drive folder.
3. Download the JSON key and place it on the **host** at `rclone/service-account.json`
   (i.e. next to `docker-compose.yml`).
   The bind-mount is already defined in `docker-compose.yml` and is automatically
   picked up when the file exists (requires Docker Compose ≥ v2.20).
4. In `.env`, uncomment and set `RCLONE_SERVICE_ACCOUNT_FILE` to the
   **in-container** path:
   ```dotenv
   RCLONE_SERVICE_ACCOUNT_FILE=/config/rclone/service-account.json
   ```
5. Leave `RCLONE_TOKEN` empty (the service account key replaces OAuth).

### 5 – Start the stack

```bash
docker compose up -d
```

Traefik routes traffic by hostname:

| URL | Service |
|---|---|
| `http://localhost` | Paperless-ngx |
| `http://ai.localhost` | Open WebUI (AI chat) |

For production, Traefik will additionally obtain a TLS certificate for your
domain via Let's Encrypt (requires DNS + ports 80/443 to be reachable).

### 6 – Create the Paperless-ngx admin user

```bash
docker compose exec paperless python3 manage.py createsuperuser
```

Open `http://localhost` (local) or `https://<PAPERLESS_DOMAIN>` (production) in
your browser and log in.

---

## Directory structure

```
.
├── docker-compose.yml          # Main stack definition
├── .env.example                # Template for environment variables
├── .gitignore
├── traefik/
│   └── acme.json               # TLS certificates (auto-generated, git-ignored)
└── rclone/
    ├── rclone.conf.example     # Example rclone config (copy → rclone.conf)
    └── sync.sh                 # Sync script run inside the rclone container
```

---

## Google Drive sync details

The `rclone-sync` service runs in the background and calls `rclone sync` on a
configurable schedule (default: **every hour**).

The following directories are mirrored to Google Drive:

| Local (Docker volume) | Google Drive path |
|---|---|
| `paperless-media` (originals + thumbnails) | `<RCLONE_DEST_PATH>/media` |
| `paperless-export` (manual exports) | `<RCLONE_DEST_PATH>/export` |

Relevant `.env` options:

| Variable | Default | Description |
|---|---|---|
| `RCLONE_REMOTE` | `gdrive` | rclone remote name in `rclone.conf` |
| `RCLONE_DEST_PATH` | `paperless-backup` | Folder path in Google Drive |
| `SYNC_INTERVAL_SECONDS` | `3600` | Seconds between syncs |

View sync logs:

```bash
docker compose logs -f rclone-sync
```

---

## Useful commands

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f

# Update all images
docker compose pull && docker compose up -d

# Backup Paperless data manually
docker compose exec paperless document_exporter ../export

# Force an immediate Google Drive sync
docker compose restart rclone-sync
```

---

## Local AI (Ollama + Open WebUI)

The stack includes a **local AI assistant** powered by [Ollama](https://ollama.com/)
and [Open WebUI](https://openwebui.com/). This gives you a ChatGPT-like interface
running entirely on your own hardware – no data leaves your server.

### Pulling the model

After the stack is running, pull the **gemma4:e4b** model (or any other Ollama
model):

```bash
docker compose exec ollama ollama pull gemma4:e4b
```

> **Tip:** The download can be several gigabytes. On subsequent starts the model
> is already cached in the `ollama-data` volume.

### Accessing the chat interface

| Setup | URL |
|---|---|
| **Local** (default) | `http://ai.localhost` |
| **Production** (Traefik + TLS) | `https://<OPEN_WEBUI_DOMAIN>` |

On first access, Open WebUI will ask you to create an admin account (unless
`OPEN_WEBUI_AUTH=false`, which is the default). After logging in, select the
**gemma4:e4b** model in the model dropdown and start chatting.

### Asking questions about your documents

Open WebUI has built-in **RAG (Retrieval Augmented Generation)** support.
You can upload documents directly in the chat using the **+** button or the
`#` shortcut to reference uploaded files. The AI will then answer questions
based on the content of those documents.

**Workflow for Paperless-ngx documents:**

1. Export documents from Paperless-ngx (or use the files in the `paperless-media`
   volume directly).
2. Upload the relevant PDFs / text files into an Open WebUI chat session.
3. Ask questions like:
   - *"Welches Dokument enthält Informationen über X?"*
   - *"Wann war der Kauf von Y?"*
   - *"Fasse die Rechnung von Z zusammen."*

> **Advanced:** Open WebUI also supports persistent **Knowledge** collections
> (under *Workspace → Knowledge*). Create a collection, upload all your
> Paperless exports into it, and reference it in any chat with `#collection-name`.
> This way you don't need to re-upload files for every conversation.

### GPU acceleration (optional)

For significantly faster inference, uncomment the `deploy` block in
`docker-compose.yml` under the `ollama` service to enable NVIDIA GPU
passthrough. You need the
[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
installed on the host.

### Useful AI commands

```bash
# Pull a model
docker compose exec ollama ollama pull gemma4:e4b

# List downloaded models
docker compose exec ollama ollama list

# Remove a model
docker compose exec ollama ollama rm gemma4:e4b

# View Ollama logs
docker compose logs -f ollama

# View Open WebUI logs
docker compose logs -f open-webui
```

---

## Traefik details

- Traefik listens on port **80** (HTTP) and **443** (HTTPS).
- For **localhost** use, everything works over plain HTTP – no certificates needed.
- For **production**, TLS certificates are issued by **Let's Encrypt** via the
  HTTP-01 challenge (requires `ACME_EMAIL` to be set to a real e-mail address).
- Certificates are stored in `traefik/acme.json` (git-ignored).
- The Traefik dashboard is **disabled** by default. To enable it, add
  `--api.dashboard=true` to the `traefik` command in `docker-compose.yml`
  and secure it with a middleware.

---

## Security notes

- `traefik/acme.json` contains TLS private keys – never commit it.
- `rclone/rclone.conf` contains OAuth tokens – never commit it.
- `.env` contains passwords and secret keys – never commit it.
- All three files are listed in `.gitignore`.
- The internal backend network (`paperless-internal`) is isolated from the
  internet; only Traefik can reach Paperless-ngx via the `proxy` network.