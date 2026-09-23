#!/usr/bin/env bash

# STUB. Submission to Test Observer is not implemented.
#
# Everything upstream of this script is real: JUnit reports are collected,
# normalised, and rendered into a submission payload. This script is where that
# payload would be POSTed, but the ingestion contract for team-supplied results
# is an open issue (SQ117 section 1.3 — "how to sandbox arbitrary uploaded
# JUnit in Test Observer"). Until that is settled, this logs what would be sent
# and exits successfully so callers can adopt the action now and get real
# submission later without changing their workflow.
#
# Required env vars:
#   PAYLOAD_FILE — output of build-payload.sh
#
# Optional env vars:
#   TEST_OBSERVER_URL   — Test Observer base URL (recorded, not called)
#   TEST_OBSERVER_TOKEN — credential (never logged)
#   PAYLOAD_PREVIEW     — "true" to print the full payload (default: false)
#
# Outputs:
#   submitted=false, submission_id="" (until implemented)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_util.sh
source "${SCRIPT_DIR}/../_util.sh"

requires jq
# curl is unused while submission is stubbed, but the real implementation needs
# it, so provision it here to keep the eventual change a one-line diff.
requires curl
require_env PAYLOAD_FILE

[ -f "$PAYLOAD_FILE" ] || die "PAYLOAD_FILE does not exist: ${PAYLOAD_FILE}"
jq -e . "$PAYLOAD_FILE" >/dev/null || die "PAYLOAD_FILE is not valid JSON: ${PAYLOAD_FILE}"

TEST_OBSERVER_URL="${TEST_OBSERVER_URL:-}"
PAYLOAD_PREVIEW="${PAYLOAD_PREVIEW:-false}"

payload_bytes=$(wc -c <"$PAYLOAD_FILE" | tr -d ' ')

tom-echo "SUBMISSION (STUB — NOTHING WAS SENT)"
tom-echo "  Endpoint:  ${TEST_OBSERVER_URL:-<unset>}"
tom-echo "  Payload:   ${PAYLOAD_FILE} (${payload_bytes} bytes)"
tom-echo "  Artefact:  $(jq -r '"\(.artefact.name) \(.artefact.version)"' "$PAYLOAD_FILE")"
tom-echo "  Results:   $(jq -r '.test_results | length' "$PAYLOAD_FILE")"
tom-echo "  Totals:    $(jq -r '.totals | "\(.passed) passed, \(.failed) failed, \(.errors) errors, \(.skipped) skipped"' "$PAYLOAD_FILE")"

if [ "$PAYLOAD_PREVIEW" = "true" ]; then
  jq . "$PAYLOAD_FILE" >&2
fi

# Intended implementation, kept here so the eventual change is a small diff:
#
#   retry curl --fail-with-body --silent --show-error \
#     -X PUT "${TEST_OBSERVER_URL}/v1/test-executions/team-results" \
#     -H "Authorization: Bearer ${TEST_OBSERVER_TOKEN}" \
#     -H "Content-Type: application/json" \
#     --data-binary "@${PAYLOAD_FILE}"

tom-echo-yellow "Test Observer submission is stubbed: results were collected and transformed but not uploaded."

set_output submitted "false"
set_output submission_id ""
