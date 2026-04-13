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
PAPERLESS_AI_TOKEN=<Paperless-ngx API token>
GEMINI_API_KEY=<your Google Gemini API key>
```

> **Hinweis:** `PAPERLESS_AI_TOKEN` wird erst nach dem ersten Start benötigt
> (siehe Schritt 6). `GEMINI_API_KEY` erhältst du kostenlos unter
> [Google AI Studio](https://aistudio.google.com/app/apikey).

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

### 5 – Create the Paperless-ngx admin user

```bash
docker compose exec paperless python3 manage.py createsuperuser
```

Open `http://localhost` (local) or `https://<PAPERLESS_DOMAIN>` (production) in
your browser and log in.

### 6 – Set up Paperless-AI

Paperless-AI erkennt neue Dokumente automatisch und vergibt Titel, Tags,
Korrespondenten und Dokumenttypen mithilfe von **Google Gemini**.

> **⚠️ Wichtig: `PAPERLESS_SECRET_KEY` ≠ API Token!**
>
> `PAPERLESS_SECRET_KEY` ist Djangos interner Schlüssel für Sessions und
> Hashing – er wird **nie** als API-Token verwendet. Der API-Token für
> Paperless-AI wird separat in der Paperless-ngx Admin-Oberfläche erstellt
> (siehe Schritt 1 unten).

#### Schritt 1: Paperless-ngx API-Token erstellen

1. Öffne Paperless-ngx im Browser (`http://localhost`).
2. Logge dich mit dem Admin-User ein (erstellt in Quick-start Schritt 5 oben).
3. Öffne den **Django-Admin**-Bereich:
   ```
   http://localhost/admin/authtoken/tokenproxy/
   ```
4. Klicke auf **"Add token"** (oder "Token hinzufügen").
5. Wähle deinen Admin-User aus dem Dropdown und klicke **"Save"**.
6. Kopiere den generierten Token (eine lange Zeichenkette, z.B.
   `a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0`).
7. Trage den Token in die `.env`-Datei ein:
   ```dotenv
   PAPERLESS_AI_TOKEN=dein-kopierter-token
   ```

#### Schritt 2: Gemini API-Key erstellen

1. Öffne [Google AI Studio](https://aistudio.google.com/app/apikey).
2. Klicke auf **"Create API key"**, wähle ein Projekt und kopiere den Key.
3. Trage den Key in die `.env`-Datei ein:
   ```dotenv
   GEMINI_API_KEY=dein-gemini-api-key
   ```

> **Tipp:** Der kostenlose Gemini-Tarif reicht für typische Dokumentenmengen
> im Heimgebrauch völlig aus.

#### Schritt 3: Container neu starten

```bash
docker compose up -d
```

#### Schritt 4: Paperless-AI Setup-Wizard durchlaufen

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
| **API Token** | Den Token aus Schritt 1 einfügen | z.B. `a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0` – das ist **nicht** der `PAPERLESS_SECRET_KEY`! |
| **Paperless-ngx Username** | Dein Paperless-ngx Admin-Benutzername | Der Benutzername, den du in Schritt 5 (`createsuperuser`) erstellt hast. |

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
| `PAPERLESS_AI_TOKEN` | API-Token aus Paperless-ngx (**nicht** `PAPERLESS_SECRET_KEY`!) – erstellt unter `/admin/authtoken/tokenproxy/` |
| `GEMINI_API_KEY` | Google Gemini API-Key ([hier erstellen](https://aistudio.google.com/app/apikey)) |
| `GEMINI_MODEL` | Modell (Standard: `gemini-2.0-flash`) |

> **⚠️ `PAPERLESS_SECRET_KEY` vs. `PAPERLESS_AI_TOKEN`:**
>
> | Variable | Zweck |
> |---|---|
> | `PAPERLESS_SECRET_KEY` | Djangos interner Schlüssel für Sessions/Hashing – wird **nie** als API-Token genutzt |
> | `PAPERLESS_AI_TOKEN` | Der API-Token, mit dem Paperless-AI auf die Paperless-ngx API zugreift |

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
