#!/usr/bin/env bash
set -euo pipefail

# Builds merged metadata JSON from auto-collected caller context and
# caller-provided metadata, then injects it into WORKFLOW_INPUTS_JSON.
#
# Required env vars:
#   WORKFLOW_INPUTS_JSON  — base workflow inputs (JSON object)
#
# Optional env vars:
#   CALLER_METADATA      — caller-provided metadata (JSON object, default: {})
#   CALLER_REPO          — caller repository (owner/name)
#   CALLER_RUN_ID        — caller workflow run ID
#   CALLER_RUN_ATTEMPT   — caller workflow run attempt
#   CALLER_ACTOR         — who triggered the caller workflow
#   CALLER_SHA           — caller commit SHA
#   CALLER_REF           — caller git ref
#   CALLER_WORKFLOW      — caller workflow name
#   CALLER_EVENT         — event that triggered the caller
#   GITHUB_SERVER_URL    — GitHub server URL (default: https://github.com)
#
# Outputs:
#   stdout: final WORKFLOW_INPUTS_JSON with metadata injected
#   GITHUB_OUTPUT (if set): workflow_inputs_json=<json>

GITHUB_SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"

# Auto-collected caller context
AUTO_META=$(jq -n \
  --arg source "${GITHUB_SERVER_URL}/${CALLER_REPO:-unknown}/actions/runs/${CALLER_RUN_ID:-0}/attempts/${CALLER_RUN_ATTEMPT:-1}" \
  --arg caller_repo "${CALLER_REPO:-}" \
  --arg caller_actor "${CALLER_ACTOR:-}" \
  --arg caller_sha "${CALLER_SHA:-}" \
  --arg caller_ref "${CALLER_REF:-}" \
  --arg caller_workflow "${CALLER_WORKFLOW:-}" \
  --arg caller_event "${CALLER_EVENT:-}" \
  '{
    source: $source,
    caller_repo: $caller_repo,
    caller_actor: $caller_actor,
    caller_sha: $caller_sha,
    caller_ref: $caller_ref,
    caller_workflow: $caller_workflow,
    caller_event: $caller_event
  }')

# Merge: auto-collected (base) + caller-provided (override)
CALLER_META="${CALLER_METADATA:-"{}"}"
if ! echo "$CALLER_META" | jq empty >/dev/null 2>&1; then
  echo "Error: CALLER_METADATA must be valid JSON." >&2
  exit 1
fi
if ! echo "$CALLER_META" | jq -e 'type == "object"' >/dev/null 2>&1; then
  echo "Error: CALLER_METADATA must be a JSON object." >&2
  exit 1
fi
MERGED_META=$(echo "$AUTO_META" | jq --argjson caller "$CALLER_META" '. * $caller')

# Inject merged metadata into workflow_inputs_json
INPUTS_JSON="${WORKFLOW_INPUTS_JSON:-"{}"}"
if ! echo "$INPUTS_JSON" | jq -e 'type == "object"' >/dev/null 2>&1; then
  echo "ERROR: WORKFLOW_INPUTS_JSON must be a valid JSON object." >&2
  exit 1
fi
FINAL_INPUTS=$(echo "$INPUTS_JSON" | jq --arg meta "$MERGED_META" '. + {metadata: $meta}')

echo "$FINAL_INPUTS"

# Write to GITHUB_OUTPUT if running in CI
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "workflow_inputs_json<<EOF"
    echo "$FINAL_INPUTS"
    echo "EOF"
  } >> "$GITHUB_OUTPUT"
fi
