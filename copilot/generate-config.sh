#!/bin/sh
# copilot/generate-config.sh – Generate GitHub Copilot config from an OAuth token.
#
# This script is executed by the copilot-config init container at every startup.
# It writes hosts.json into the shared copilot-config volume so that the
# copilot-openai-api container finds a ready-made configuration.
#
# Required environment variable (set in .env):
#   GITHUB_COPILOT_OAUTH_TOKEN  – GitHub OAuth token from your Copilot IDE plugin
#                                  (starts with gho_ or ghu_, found in
#                                   ~/.config/github-copilot/hosts.json or apps.json)

set -e

CONFIG_DIR="/config/github-copilot"
HOSTS_FILE="${CONFIG_DIR}/hosts.json"

if [ -z "${GITHUB_COPILOT_OAUTH_TOKEN:-}" ]; then
    echo "ERROR: GITHUB_COPILOT_OAUTH_TOKEN is not set. Add it to your .env file." >&2
    echo "" >&2
    echo "How to find your token:" >&2
    echo "  Linux/macOS: cat ~/.config/github-copilot/hosts.json" >&2
    echo "  Windows:     type %LOCALAPPDATA%\\github-copilot\\hosts.json" >&2
    echo "  Look for the \"oauth_token\" value." >&2
    exit 1
fi

mkdir -p "${CONFIG_DIR}"

echo "Generating GitHub Copilot hosts.json ..."
cat > "${HOSTS_FILE}" <<EOF
{
  "github.com": {
    "oauth_token": "${GITHUB_COPILOT_OAUTH_TOKEN}"
  }
}
EOF

echo "hosts.json written to ${HOSTS_FILE}"
