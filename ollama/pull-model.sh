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
wget -qO- --post-data "{\"name\":\"${MODEL}\"}" \
     --header "Content-Type: application/json" \
     "${OLLAMA_URL}/api/pull" | while IFS= read -r line; do
  # Print progress lines (Ollama streams JSON)
  status=$(echo "$line" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
  [ -n "$status" ] && echo "  $status"
done

echo "Model '${MODEL}' is ready."
