# Paperless-ngx + Paperless-AI + Google Drive Sync + Traefik

A ready-to-run Docker Compose stack that combines:

| Component | Purpose |
|---|---|
| **[Paperless-ngx](https://docs.paperless-ngx.com/)** | Document management system (scan, OCR, tag, search) |
| **[Paperless-AI](https://github.com/clusterzx/paperless-ai)** | Automatic AI tagging & classification for new documents (powered by local Ollama / gemma4:e4b) |
| **[Ollama](https://ollama.com/)** | Local LLM inference engine (runs gemma4:e4b) |
| **[copilot-openai-api](https://github.com/yuchanns/copilot-openai-api)** | GitHub Copilot → OpenAI-compatible API proxy (alternative to Ollama) |
| **[PostgreSQL 16](https://www.postgresql.org/)** | Database for Paperless-ngx |
| **[Redis 7](https://redis.io/)** | Task queue / message broker |
| **[Gotenberg](https://gotenberg.dev/)** | Document → PDF conversion (DOCX, XLSX, …) |
| **[Apache Tika](https://tika.apache.org/)** | Content extraction for full-text search |
| **[rclone](https://rclone.org/)** | Periodic sync of documents to **Google Drive** |
| **[Traefik v3](https://traefik.io/traefik/)** | Reverse proxy with TLS (self-signed locally, optional Let's Encrypt for production) |

---

## Prerequisites

- A Linux machine (or macOS / Windows with Docker Desktop) with Docker ≥ 24 and Docker Compose v2 (`docker compose`).
- **Recommended:** A machine with at least 16 GB RAM for local AI inference (runs on CPU).
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
```

> **Hinweis:** `PAPERLESS_AI_TOKEN` wird erst nach dem ersten Start benötigt
> (siehe Schritt 6). Das Ollama-Modell (`gemma4:e4b`) wird beim ersten Start
> automatisch heruntergeladen – eine Internetverbindung ist dafür erforderlich.

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

Choose an **AI backend** by starting with the matching Docker Compose profile:

```bash
# Option A: Local Ollama (runs models on CPU, default)
docker compose --profile ollama up -d

# Option B: GitHub Copilot (requires Copilot subscription, see section below)
docker compose --profile copilot up -d
```

> **Hinweis:** Du kannst auch beide Profile gleichzeitig starten:
> `docker compose --profile ollama --profile copilot up -d`
> Paperless-AI verbindet sich aber nur mit dem Backend, das in `.env`
> konfiguriert ist (siehe `CUSTOM_BASE_URL`).

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
Korrespondenten und Dokumenttypen mithilfe eines **lokalen Ollama-Modells**
(`gemma4:e4b` per Standard).

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

#### Schritt 2: Container starten

Das Ollama-Modell wird beim ersten Start automatisch heruntergeladen.
Dies kann je nach Internetgeschwindigkeit einige Minuten dauern.

```bash
docker compose up -d
```

> **Tipp:** Den Download-Fortschritt kannst du mit
> `docker compose logs -f ollama-pull` verfolgen.

#### Schritt 3: Paperless-AI Setup-Wizard durchlaufen

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

**Bei Ollama-Backend:**

| Feld | Was eingeben | Erklärung |
|---|---|---|
| **AI Provider** | `Custom / OpenAI compatible` auswählen | Wir nutzen die lokale Ollama-Instanz über den OpenAI-kompatiblen Endpunkt. |
| **Custom Base URL** | `http://ollama:11434/v1/` | OpenAI-kompatibler Endpunkt des lokalen Ollama-Servers. |
| **Custom API Key** | `ollama` | Ollama benötigt keinen echten API-Key – ein beliebiger Wert reicht. |
| **Custom Model** | `gemma4:e4b` | Lokales Modell. Alternativ: `llama3.1`, `mistral`, `gemma2`. |

> **Hinweis:** Beim ersten Start muss das Ollama-Modell zunächst
> heruntergeladen werden (Container `ollama-pull`). Paperless-AI startet
> parallel und kann erst AI-Anfragen verarbeiten, wenn der Download
> abgeschlossen ist. Fortschritt prüfen:
> `docker compose logs -f ollama-pull`

**Bei Copilot-Backend:**

| Feld | Was eingeben | Erklärung |
|---|---|---|
| **AI Provider** | `Custom / OpenAI compatible` auswählen | GitHub Copilot wird über den OpenAI-kompatiblen Proxy angesprochen. |
| **Custom Base URL** | `http://copilot-openai-api:9191/v1/` | Endpunkt des copilot-openai-api Proxys. |
| **Custom API Key** | Dein `COPILOT_TOKEN` | Der Token, den du in `.env` konfiguriert hast. |
| **Custom Model** | `gpt-4o` | GitHub Copilot Modell. Alternativ: `gpt-4o-mini`, `gpt-4`, `o1-mini`. |

> **Tipp:** Falls die Felder vorausgefüllt sind (aus den Umgebungsvariablen
> in `docker-compose.yml`), kontrolliere nur die Werte und klicke weiter.

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
├── copilot/
│   └── generate-config.sh      # Init script to generate Copilot config from OAuth token
├── ollama/
│   └── pull-model.sh           # Init script to pull the Ollama model on startup
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
# Start all services with Ollama (local AI)
docker compose --profile ollama up -d

# Start all services with GitHub Copilot (cloud AI)
docker compose --profile copilot up -d

# Stop all services
docker compose --profile ollama down
# or
docker compose --profile copilot down

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

Die AI-Analyse kann über zwei Backends laufen:

| Backend | Beschreibung | Profil |
|---|---|---|
| **Ollama** (Standard) | Lokales Modell `gemma4:e4b` – komplett lokal auf der CPU, ohne Cloud-API | `--profile ollama` |
| **GitHub Copilot** | Über [copilot-openai-api](https://github.com/yuchanns/copilot-openai-api) – nutzt dein GitHub-Copilot-Abo | `--profile copilot` |

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
| `AI_PROVIDER` | AI-Provider für Paperless-AI (Standard: `custom`) |
| `CUSTOM_BASE_URL` | OpenAI-kompatible Basis-URL (Ollama: `http://ollama:11434/v1/`, Copilot: `http://copilot-openai-api:9191/v1/`) |
| `CUSTOM_API_KEY` | API-Key für das Backend (Ollama: `ollama`, Copilot: dein `COPILOT_TOKEN`) |
| `CUSTOM_MODEL` | Modell-Name (Ollama: `gemma4:e4b`, Copilot: z.B. `gpt-4o`) |
| `OLLAMA_MODEL` | Ollama-Modell (Standard: `gemma4:e4b`) – nur relevant bei Ollama-Backend |

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

# Ollama Logs anzeigen (Modellanfragen)
docker compose logs -f ollama

# Ollama Model-Pull Fortschritt anzeigen
docker compose logs -f ollama-pull

# Paperless-AI neu starten (z.B. nach .env-Änderungen)
docker compose restart paperless-ai
```

---

## GitHub Copilot als AI-Backend (Alternative zu Ollama)

Anstatt ein lokales LLM über Ollama zu hosten, kannst du **GitHub Copilot**
als AI-Backend nutzen. Der
[copilot-openai-api](https://github.com/yuchanns/copilot-openai-api)-Proxy
macht die GitHub Copilot API OpenAI-kompatibel – dadurch funktioniert er
nahtlos mit Paperless-AI.

### Voraussetzungen

- Ein **GitHub-Konto mit aktivem Copilot-Abo** (Individual, Business oder
  Enterprise).
- Ein IDE-Plugin (VS Code, IntelliJ, Vim, …) muss **einmalig** installiert
  und mit deinem GitHub-Konto angemeldet werden, um den OAuth-Token zu
  erhalten.

### Schritt 1: GitHub OAuth-Token finden

Nach dem Anmelden in einem unterstützten IDE-Plugin wird der Token
automatisch gespeichert:

```bash
# Linux / macOS:
cat ~/.config/github-copilot/hosts.json

# Windows (PowerShell):
type $env:LOCALAPPDATA\github-copilot\hosts.json
```

Suche den Wert von `"oauth_token"` – er beginnt meist mit `gho_` oder `ghu_`.

### Schritt 2: `.env` konfigurieren

Kommentiere die **Ollama-Variablen** aus und aktiviere die
**Copilot-Variablen**:

```dotenv
# ── Option B: GitHub Copilot ──────────────────────────────────────────
AI_PROVIDER=custom
CUSTOM_BASE_URL=http://copilot-openai-api:9191/v1/
CUSTOM_API_KEY=mein-geheimer-token
CUSTOM_MODEL=gpt-4o

# Bearer-Token für den copilot-openai-api Proxy (muss mit CUSTOM_API_KEY
# übereinstimmen):
COPILOT_TOKEN=mein-geheimer-token

# Dein GitHub OAuth-Token (das ist alles, was du brauchst!):
GITHUB_COPILOT_OAUTH_TOKEN=gho_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

> **Tipp:** Generiere ein sicheres `COPILOT_TOKEN` mit:
> ```bash
> python3 -c "import secrets; print(secrets.token_hex(32))"
> ```

### Schritt 3: Mit Copilot-Profil starten

```bash
docker compose --profile copilot up -d
```

Der `copilot-config`-Init-Container erzeugt automatisch die nötige
Konfigurationsdatei aus deinem OAuth-Token – kein Config-Pfad-Mounting nötig.

### Schritt 4: Paperless-AI Setup-Wizard

Öffne `http://localhost:3000` und durchlaufe den Wizard. Im Tab
**AI Settings**:

| Feld | Wert |
|---|---|
| **AI Provider** | `Custom / OpenAI compatible` |
| **Custom Base URL** | `http://copilot-openai-api:9191/v1/` |
| **Custom API Key** | Dein `COPILOT_TOKEN` |
| **Custom Model** | `gpt-4o` (oder ein anderes von Copilot unterstütztes Modell) |

### Verfügbare Copilot-Modelle

Eine Liste der verfügbaren Modelle erhältst du über:

```bash
curl http://localhost:9191/v1/models \
  -H "Authorization: Bearer dein-copilot-token"
```

Gängige Modelle: `gpt-4o`, `gpt-4o-mini`, `gpt-4`, `claude-sonnet-4`,
`o1-preview`, `o1-mini`.

### Nützliche Befehle (Copilot)

```bash
# Copilot API Proxy Logs anzeigen
docker compose logs -f copilot-openai-api

# Copilot Config Init-Container Logs anzeigen
docker compose logs copilot-config

# Copilot API testen
curl -X POST http://localhost:9191/v1/chat/completions \
  -H "Authorization: Bearer dein-copilot-token" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hello!"}]}'

# Zwischen Ollama und Copilot wechseln:
# 1. .env anpassen (CUSTOM_BASE_URL, CUSTOM_API_KEY, CUSTOM_MODEL)
# 2. Altes Profil stoppen, neues starten:
docker compose --profile ollama down
docker compose --profile copilot up -d
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