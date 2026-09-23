#!/usr/bin/env bash

# Runs the full collect -> transform -> submit pipeline.
#
# This is the entry point for local runs and the reference for what the
# composite action does. The action invokes the same scripts as separate steps
# purely so each phase gets its own log group; it adds no logic of its own.
#
# Every env var consumed by the individual scripts applies here. Minimum:
#   JUNIT_PATHS, TO_ARTEFACT_NAME, TO_ARTEFACT_VERSION, TO_ENVIRONMENT
#
# Example:
#   JUNIT_PATHS='reports/**/*.xml' \
#   TO_ARTEFACT_NAME=my-charm \
#   TO_ARTEFACT_VERSION=42 \
#   TO_ENVIRONMENT=local \
#   ./run.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_util.sh
source "${SCRIPT_DIR}/../_util.sh"

export OUTPUT_FILE="${OUTPUT_FILE:-$(work_dir test-observer-publisher)/normalised-results.json}"
"${SCRIPT_DIR}/collect-junit.sh"

export NORMALISED_FILE="$OUTPUT_FILE"
export PAYLOAD_FILE="${PAYLOAD_FILE:-$(work_dir test-observer-publisher)/payload.json}"
"${SCRIPT_DIR}/build-payload.sh"

"${SCRIPT_DIR}/submit-results.sh"
