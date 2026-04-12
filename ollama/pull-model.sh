#!/bin/sh
# pull-model.sh – wait for Ollama to be ready, then pull the configured model.
# Used as an init container so the model is available when Open WebUI starts.
set -e

MODEL="${OLLAMA_MODEL:-gemma4:e4b}"
OLLAMA_URL="${OLLAMA_BASE_URL:-http://ollama:11434}"

echo "Waiting for Ollama at ${OLLAMA_URL} ..."
until wget -qO /dev/null "${OLLAMA_URL}/api/tags" 2>/dev/null; do
  sleep 2
done
echo "Ollama is ready."

echo "Pulling model '${MODEL}' ..."

# Store the streaming response in a temp file so we can both show progress
# lines and inspect the final line for errors (Ollama returns {"error":"..."}
# on failure or {"status":"success"} on success).
PULL_TMPFILE=$(mktemp)
trap 'rm -f "${PULL_TMPFILE}"' EXIT INT TERM
wget -qO "${PULL_TMPFILE}" --post-data "{\"name\":\"${MODEL}\"}" \
     --header "Content-Type: application/json" \
     "${OLLAMA_URL}/api/pull"

# Print progress from stored response
while IFS= read -r line; do
  status=$(echo "$line" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
  [ -n "$status" ] && echo "  $status"
done < "${PULL_TMPFILE}"

LAST_LINE=$(tail -1 "${PULL_TMPFILE}")
rm -f "${PULL_TMPFILE}"

# Detect application-level pull errors (HTTP 200 with {"error":"..."} body)
if echo "${LAST_LINE}" | grep -q '"error"'; then
  err=$(echo "${LAST_LINE}" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
  echo "ERROR: Failed to pull model '${MODEL}': ${err}" >&2
  exit 1
fi

echo "Model '${MODEL}' is ready."
