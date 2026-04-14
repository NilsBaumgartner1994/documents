# Paperless-ngx + Paperless-AI + Google Drive Sync + Traefik

A ready-to-run Docker Compose stack that combines:

| Component | Purpose |
|---|---|
| **[Paperless-ngx](https://docs.paperless-ngx.com/)** | Document management system (scan, OCR, tag, search) |
| **[Paperless-AI](https://github.com/clusterzx/paperless-ai)** | Automatic AI tagging & classification for new documents (powered by Google Gemini) |
| **[PostgreSQL 16](https://www.postgresql.org/)** | Database for Paperless-ngx |
| **[Redis 7](https://redis.io/)** | Task queue / message broker |
| **[Gotenberg](https://gotenberg.dev/)** | Document → PDF conversion (DOCX, XLSX, …) |
| **[Apache Tika](https://tika.apache.org/)** | Content extraction for full-text search |
| **[rclone](https://rclone.org/)** | Periodic sync of documents to **Google Drive** |
| **[Traefik v3](https://traefik.io/traefik/)** | Reverse proxy with TLS (self-signed locally, optional Let's Encrypt for production) |

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
PAPERLESS_ADMIN_PASSWORD=<strong admin password>
```

> **Hinweis:** Der Admin-User wird beim ersten Start automatisch erstellt
> (kein manuelles `createsuperuser` nötig). Der API-Token für Paperless-AI
> wird ebenfalls automatisch abgerufen – dazu müssen `PAPERLESS_ADMIN_USER`
> und `PAPERLESS_ADMIN_PASSWORD` in `.env` gesetzt sein (sind standardmäßig
> vorkonfiguriert).

The defaults are set for **local use** (`localhost`).
For production, also update:

```dotenv
PAPERLESS_DOMAIN=paperless.example.com
PAPERLESS_URL=https://paperless.example.com
ACME_EMAIL=your-email@example.com          # required for Let's Encrypt (see README)
```

Generate a secure secret key:

```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

### 3 – Configure rclone for Google Drive

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

### 4 – Start the stack

```bash
docker compose up -d
```

Traefik routes traffic by hostname (both HTTP and HTTPS):

| URL | Service |
|---|---|
| `http://localhost` / `https://localhost` | Paperless-ngx (Dokumentenverwaltung) |
| `http://localhost:3000` | Paperless-AI Web UI (Einrichtung & Übersicht) |

> **Hinweis:** Paperless-AI hat eine **eigene Web-Oberfläche auf Port 3000**.
> Diese ist *nicht* über Traefik erreichbar, sondern direkt über den Port.
> Du öffnest sie einfach im Browser unter `http://<deine-IP>:3000`.

> **Note:** For localhost the HTTPS certificate is self-signed. Your browser may
> show a security warning – accept it to continue. For production with a real
> domain you can configure automatic Let's Encrypt certificates (see
> [Traefik details](#traefik-details) below).

### 5 – Paperless-ngx Admin-User

Der Admin-User wird beim ersten Start **automatisch** aus den `.env`-Variablen
`PAPERLESS_ADMIN_USER` und `PAPERLESS_ADMIN_PASSWORD` erstellt. Du kannst dich
direkt unter `http://localhost` (oder `https://<PAPERLESS_DOMAIN>`) einloggen.

> **Manuell nachträglich einen Superuser anlegen** (falls nötig):
>
> ```bash
> docker compose exec paperless python3 manage.py createsuperuser
> ```

### 6 – Set up Paperless-AI

Paperless-AI erkennt neue Dokumente automatisch und vergibt Titel, Tags,
Korrespondenten und Dokumenttypen mithilfe eines **AI-Backends** (GitHub
Copilot via copilot-api ist als Standard konfiguriert).

> **API-Token:** Der Token für die Paperless-ngx API wird beim Start von
> Paperless-AI **automatisch** abgerufen, wenn `PAPERLESS_ADMIN_USER` und
> `PAPERLESS_ADMIN_PASSWORD` in `.env` gesetzt sind. Ein manuelles Erstellen
> des Tokens ist nicht mehr nötig.
>
> Alternativ kann ein Token manuell gesetzt werden:
> ```dotenv
> PAPERLESS_AI_TOKEN=dein-manuell-erstellter-token
> ```

> **⚠️ Wichtig: `PAPERLESS_SECRET_KEY` ≠ API Token!**
>
> `PAPERLESS_SECRET_KEY` ist Djangos interner Schlüssel für Sessions und
> Hashing – er wird **nie** als API-Token verwendet.

#### Schritt 1: Paperless-AI Setup-Wizard durchlaufen

Öffne die Paperless-AI Oberfläche im Browser:

```
http://localhost:3000
```

Beim ersten Start wirst du durch einen **Einrichtungsassistenten** mit
mehreren Tabs geführt. Hier eine Anleitung für jeden Tab:

---

##### Tab 1: User Setup

| Feld | Was eingeben |
|---|---|
| **Admin Username** | Frei wählbar – das ist der Login-Name für die Paperless-AI Web-Oberfläche (z.B. `admin`). |
| **Admin Password** | Frei wählbar – ein sicheres Passwort für die Paperless-AI Web-Oberfläche. |

> **Hinweis:** Dieser Benutzer ist **nur für die Paperless-AI Web UI** – er hat
> nichts mit dem Paperless-ngx Admin-User zu tun.

---

##### Tab 2: Connection

Hier wird die Verbindung zu Paperless-ngx konfiguriert.

| Feld | Was eingeben | Erklärung |
|---|---|---|
| **Paperless-ngx API URL** | `http://paperless:8000` | Der Docker-Service-Name aus `docker-compose.yml`. **Nicht** `localhost` verwenden – das funktioniert nicht zwischen Docker-Containern! **Ohne** `/api` am Ende eingeben – der Pfad wird automatisch angehängt. |
| **API Token** | Wird automatisch gesetzt | Wenn `PAPERLESS_ADMIN_USER` / `PAPERLESS_ADMIN_PASSWORD` in `.env` gesetzt sind, wird der Token automatisch abgerufen. Alternativ manuell einfügen. |
| **Paperless-ngx Username** | Dein Paperless-ngx Admin-Benutzername | Der Benutzername aus `PAPERLESS_ADMIN_USER` in `.env` (Standard: `admin`). |

> **⚠️ Häufiger Fehler:** `localhost` oder `127.0.0.1` funktioniert **nicht**
> im Docker-Bridge-Netzwerk. Der Container-Name `paperless` wird über das
> interne Docker-Netzwerk (`paperless-internal`) aufgelöst.

---

##### Tab 3: AI Settings

AI_PROVIDER: custom
CUSTOM_BASE_URL: http://copilot-api:4141/v1/
CUSTOM_API_KEY: copilot   # any non-empty value; copilot-api does not validate it
CUSTOM_MODEL: ${COPILOT_MODEL:-claude-3.5-sonnet}

---

##### Tab 4: Advanced

Hier kannst du erweiterte Einstellungen vornehmen. Die Standardwerte sind
für den Anfang in Ordnung. Klicke auf **"Save"** / **"Finish"**, um den
Setup-Wizard abzuschließen.

---

Nach dem Abschluss des Wizards startet Paperless-AI automatisch und
überwacht neue Dokumente in Paperless-ngx.

---

## Directory structure

```
.
├── docker-compose.yml          # Main stack definition
├── .env.example                # Template for environment variables
├── .gitignore
├── scripts/
│   └── paperless-ai-entrypoint.sh  # Wrapper: auto-fetches Paperless API token
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

## Paperless-AI (automatische Dokument-Klassifikation)

Der Stack enthält [Paperless-AI](https://github.com/clusterzx/paperless-ai)
von **clusterzx**. Dieser Dienst überwacht Paperless-ngx auf neue Dokumente
und vergibt automatisch:

- **Titel**
- **Tags**
- **Korrespondenten**
- **Dokumenttypen**

Die AI-Analyse läuft über **Google Gemini** (Cloud-API). Es wird kein lokales
LLM oder GPU benötigt – ein kostenloser Gemini-API-Key reicht aus.

### Web UI aufrufen

Die Paperless-AI Web-Oberfläche ist erreichbar unter:

| Setup | URL |
|---|---|
| **Lokal** (Standard) | `http://localhost:3000` |
| **Remote / Server** | `http://<deine-server-ip>:3000` |

> **Wichtig:** Die Web UI läuft auf **Port 3000** und ist *nicht* über
> Traefik geroutet. Du rufst sie direkt über den Port auf.

### Was kann die Web UI?

- Einrichtungsassistent beim ersten Start
- Übersicht über verarbeitete Dokumente
- AI-Einstellungen anpassen (Modell, Prompt, etc.)
- Verbindung zu Paperless-ngx verwalten

### Relevante `.env`-Variablen

| Variable | Beschreibung |
|---|---|
| `PAPERLESS_ADMIN_USER` | Admin-Benutzername für Paperless-ngx (Standard: `admin`) – wird beim ersten Start automatisch erstellt |
| `PAPERLESS_ADMIN_PASSWORD` | Admin-Passwort für Paperless-ngx – wird für die automatische Token-Abfrage benötigt |
| `PAPERLESS_AI_TOKEN` | (Optional) API-Token manuell setzen. Wenn leer, wird der Token automatisch über die Admin-Credentials abgerufen |
| `COPILOT_MODEL` | AI-Modell (Standard: `claude-3.5-sonnet`) |

> **⚠️ `PAPERLESS_SECRET_KEY` vs. `PAPERLESS_AI_TOKEN`:**
>
> | Variable | Zweck |
> |---|---|
> | `PAPERLESS_SECRET_KEY` | Djangos interner Schlüssel für Sessions/Hashing – wird **nie** als API-Token genutzt |
> | `PAPERLESS_AI_TOKEN` | (Optional) Der API-Token, mit dem Paperless-AI auf die Paperless-ngx API zugreift |

### Nützliche Befehle

```bash
# Paperless-AI Logs anzeigen
docker compose logs -f paperless-ai

# Paperless-AI neu starten (z.B. nach .env-Änderungen)
docker compose restart paperless-ai
```

---

## Traefik details

- Traefik listens on port **80** (HTTP) and **443** (HTTPS).
- For **localhost** use, HTTPS is served with Traefik's built-in **self-signed
  certificate**. Your browser will show a certificate warning, but the
  connection is encrypted.
- For **production** with automatic **Let's Encrypt** TLS, add the following to
  `docker-compose.yml` under the `traefik` service `command`:
  ```yaml
  - "--certificatesresolvers.letsencrypt.acme.email=${ACME_EMAIL}"
  - "--certificatesresolvers.letsencrypt.acme.storage=/acme.json"
  - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
  - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
  ```
  Mount the certificate store: `- ./traefik/acme.json:/acme.json` (create it
  with `touch traefik/acme.json && chmod 600 traefik/acme.json`).
  Then add the label `traefik.http.routers.<name>-secure.tls.certresolver=letsencrypt`
  to each service that needs a real certificate.
- The Traefik dashboard is **disabled** by default. To enable it, add
  `--api.dashboard=true` to the `traefik` command in `docker-compose.yml`
  and secure it with a middleware.

---

## Security notes

- `rclone/rclone.conf` contains OAuth tokens – never commit it.
- `.env` contains passwords and secret keys – never commit it.
- Both files are listed in `.gitignore`.
- The internal backend network (`paperless-internal`) is isolated from the
  internet; only Traefik can reach Paperless-ngx via the `proxy` network.
