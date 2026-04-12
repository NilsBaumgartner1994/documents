# Paperless-ngx + Google Drive Sync + Traefik

A ready-to-run Docker Compose stack that combines:

| Component | Purpose |
|---|---|
| **[Paperless-ngx](https://docs.paperless-ngx.com/)** | Document management system (scan, OCR, tag, search) |
| **[PostgreSQL 16](https://www.postgresql.org/)** | Database for Paperless-ngx |
| **[Redis 7](https://redis.io/)** | Task queue / message broker |
| **[Gotenberg](https://gotenberg.dev/)** | Document → PDF conversion (DOCX, XLSX, …) |
| **[Apache Tika](https://tika.apache.org/)** | Content extraction for full-text search |
| **[rclone](https://rclone.org/)** | Periodic sync of documents to **Google Drive** |
| **[Traefik v3](https://traefik.io/traefik/)** | Reverse proxy with automatic **Let's Encrypt** TLS |

---

## Prerequisites

- A Linux server with Docker ≥ 24 and Docker Compose v2 (`docker compose`) installed.
- A public domain name pointing to the server's IP (required for Let's Encrypt).
- Ports **80** and **443** open in your firewall / security group.
- A Google account (for Google Drive sync).

---

## Quick-start

### 1 – Clone & copy environment file

```bash
git clone https://github.com/NilsBaumgartner1994/documents.git
cd documents
cp .env.example .env
```

### 2 – Edit `.env`

Open `.env` and fill in **all required values**:

```dotenv
ACME_EMAIL=your-email@example.com       # Let's Encrypt notifications
PAPERLESS_DOMAIN=paperless.example.com  # Your public domain
PAPERLESS_SECRET_KEY=<random 64-char string>
PAPERLESS_DBPASS=<strong password>
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
4. Add a bind-mount for the key file to the `rclone-config` service in
   `docker-compose.yml`:
   ```yaml
   rclone-config:
     volumes:
       - rclone-config:/config/rclone
       - ./rclone/generate-config.sh:/generate-config.sh:ro
       - ./rclone/service-account.json:/config/rclone/service-account.json:ro   # ← add this
   ```
5. In `.env`, uncomment and set `RCLONE_SERVICE_ACCOUNT_FILE` to the
   **in-container** path (this is different from the host path above):
   ```dotenv
   RCLONE_SERVICE_ACCOUNT_FILE=/config/rclone/service-account.json
   ```
6. Leave `RCLONE_TOKEN` empty (the service account key replaces OAuth).

### 5 – Start the stack

```bash
docker compose up -d
```

Traefik will automatically obtain a TLS certificate for `PAPERLESS_DOMAIN` on
first start (requires DNS to be configured and ports 80/443 to be reachable).

### 6 – Create the Paperless-ngx admin user

```bash
docker compose exec paperless python3 manage.py createsuperuser
```

Open `https://<PAPERLESS_DOMAIN>` in your browser and log in.

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

## Running locally (no public domain)

If you just want to try the stack on your own machine without a public domain
or TLS certificate, use the provided `docker-compose.local.yml` override.  It
disables Traefik and exposes Paperless-ngx directly on port **8000** via plain
HTTP.

### 1 – Set the required `.env` values

```dotenv
PAPERLESS_DOMAIN=localhost          # used only as a label; Traefik is disabled
ACME_EMAIL=local@localhost          # any value is fine – ACME is not used
PAPERLESS_SECRET_KEY=<random string>
PAPERLESS_DBPASS=<password>
```

### 2 – Start the stack with the local override

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
```

### 3 – Create the admin user

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml \
  exec paperless python3 manage.py createsuperuser
```

Open **http://localhost:8000** in your browser and log in.

> **Note:** The rclone Google Drive sync is included in the local stack as well.
> If you don't need it, comment out the `rclone-config` and `rclone-sync`
> services in `docker-compose.yml`.

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

## Traefik details

- HTTP (port 80) is automatically redirected to HTTPS (port 443).
- TLS certificates are issued by **Let's Encrypt** via the HTTP-01 challenge.
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