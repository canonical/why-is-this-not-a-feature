#!/usr/bin/env bash

# Transforms the normalised JUnit document into a Test Observer submission
# payload.
#
# NOTE: the payload schema below is PROVISIONAL. Test Observer's ingestion
# contract for team-supplied results is still an open issue in SQ117 section
# 1.3, so this script encodes a best guess modelled on the existing
# start-test / end-test API. When the real contract lands, this script is the
# only place that needs to change.
#
# Required env vars:
#   NORMALISED_FILE     — output of collect-junit.sh
#   TO_ARTEFACT_NAME    — artefact the results belong to (e.g. the charm name)
#   TO_ARTEFACT_VERSION — artefact revision / version
#   TO_ENVIRONMENT      — environment the tests ran against
#
# Optional env vars:
#   PAYLOAD_FILE       — where to write the payload (default: <work_dir>/payload.json)
#   TO_FAMILY          — artefact family (default: charm)
#   TO_TRACK           — store track
#   TO_STORE           — store name
#   TO_SERIES          — series
#   TO_ARCH            — architecture (default: runner arch)
#   TO_EXECUTION_STAGE — execution stage (default: candidate)
#   TO_TEST_PLAN       — test plan identifier (default: derived from source repo)
#   TO_CI_LINK         — link back to the CI run that produced the results
#   TO_METADATA_JSON   — arbitrary JSON object merged into payload.metadata
#
# Outputs:
#   PAYLOAD_FILE on disk, and the payload_file GitHub Action step output.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_util.sh
source "${SCRIPT_DIR}/../_util.sh"

requires jq
require_env NORMALISED_FILE TO_ARTEFACT_NAME TO_ARTEFACT_VERSION TO_ENVIRONMENT

[ -f "$NORMALISED_FILE" ] || die "NORMALISED_FILE does not exist: ${NORMALISED_FILE}"

PAYLOAD_FILE="${PAYLOAD_FILE:-$(work_dir test-observer-publisher)/payload.json}"

TO_METADATA_JSON="${TO_METADATA_JSON:-}"
[ -n "$TO_METADATA_JSON" ] || TO_METADATA_JSON='{}'
if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$TO_METADATA_JSON"; then
  die "TO_METADATA_JSON must be a valid JSON object."
fi

# CI context, auto-collected the same way the remote workflow executor does it.
CI_LINK="${TO_CI_LINK:-}"
if [ -z "$CI_LINK" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
  CI_LINK="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID:-0}/attempts/${GITHUB_RUN_ATTEMPT:-1}"
fi

mkdir -p "$(dirname "$PAYLOAD_FILE")"

jq \
  --arg family "${TO_FAMILY:-charm}" \
  --arg name "$TO_ARTEFACT_NAME" \
  --arg version "$TO_ARTEFACT_VERSION" \
  --arg track "${TO_TRACK:-}" \
  --arg store "${TO_STORE:-}" \
  --arg series "${TO_SERIES:-}" \
  --arg arch "${TO_ARCH:-${RUNNER_ARCH:-}}" \
  --arg execution_stage "${TO_EXECUTION_STAGE:-candidate}" \
  --arg environment "$TO_ENVIRONMENT" \
  --arg test_plan "${TO_TEST_PLAN:-${GITHUB_REPOSITORY:-unknown}}" \
  --arg ci_link "$CI_LINK" \
  --arg source_repo "${GITHUB_REPOSITORY:-}" \
  --arg source_sha "${GITHUB_SHA:-}" \
  --arg source_ref "${GITHUB_REF:-}" \
  --argjson extra_metadata "$TO_METADATA_JSON" \
  '
  # Test Observer records PASSED / FAILED / SKIPPED only. JUnit <error> is
  # collapsed into FAILED, with the distinction preserved in the comment so
  # triage can still tell a crash from an assertion.
  def to_status: if . == "ERROR" then "FAILED" elif . == "UNKNOWN" then "FAILED" else . end;
  def qualified_name: if .classname == "" then .name else "\(.classname)::\(.name)" end;
  def comment:
    if .status == "ERROR" then (["[error]", .message] | map(select(. != "")) | join(" "))
    elif .status == "UNKNOWN" then (["[unrecognised junit outcome]", .message] | map(select(. != "")) | join(" "))
    else .message
    end;

  {
    schema_version: "test-observer-submission/v0-draft",
    artefact: ({
      family: $family,
      name: $name,
      version: $version,
      track: $track,
      store: $store,
      series: $series,
      arch: $arch
    } | with_entries(select(.value != ""))),
    test_execution: ({
      execution_stage: $execution_stage,
      environment: $environment,
      test_plan: $test_plan,
      ci_link: $ci_link,
      collected_at: .collected_at
    } | with_entries(select(.value != ""))),
    metadata: (({
      pillar: "team-supplied",
      source_repo: $source_repo,
      source_sha: $source_sha,
      source_ref: $source_ref,
      source_files: .source_files
    } | with_entries(select(.value != "" and .value != null))) * $extra_metadata),
    totals: .totals,
    test_results: [
      .suites[] as $suite
      | $suite.cases[]
      | {
          name: qualified_name,
          suite: $suite.name,
          status: (.status | to_status),
          duration: .duration,
          comment: comment,
          io_log: .details
        }
    ]
  }
  ' "$NORMALISED_FILE" >"$PAYLOAD_FILE"

result_count=$(jq -r '.test_results | length' "$PAYLOAD_FILE")

tom-echo "TEST OBSERVER PAYLOAD"
tom-echo "  Artefact:    ${TO_ARTEFACT_NAME} ${TO_ARTEFACT_VERSION} (${TO_FAMILY:-charm})"
tom-echo "  Environment: ${TO_ENVIRONMENT}"
tom-echo "  Stage:       ${TO_EXECUTION_STAGE:-candidate}"
tom-echo "  Results:     ${result_count}"
tom-echo "  Output:      ${PAYLOAD_FILE}"

set_output payload_file "$PAYLOAD_FILE"
