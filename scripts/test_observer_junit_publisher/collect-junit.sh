#!/usr/bin/env bash

# Collects JUnit XML reports and normalises them into a single JSON document.
#
# The normalised document is the contract between collection and submission:
# it is deliberately independent of both the JUnit dialect that produced it and
# the Test Observer API that consumes it, so either side can change without
# touching the other.
#
# Required env vars:
#   JUNIT_PATHS   — newline- or space-separated file paths / globs (globstar enabled)
#
# Optional env vars:
#   OUTPUT_FILE          — where to write the normalised JSON
#                          (default: <work_dir>/normalised-results.json)
#   FAIL_ON_NO_RESULTS   — "true" to exit non-zero when no test cases are found
#                          (default: true)
#
# Outputs:
#   OUTPUT_FILE on disk, and these GitHub Action step outputs:
#     normalised_file, total_tests, passed, failed, errors, skipped

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_util.sh
source "${SCRIPT_DIR}/../_util.sh"

requires jq
requires xmlstarlet
require_env JUNIT_PATHS

WORK_DIR="$(work_dir test-observer-publisher)"
OUTPUT_FILE="${OUTPUT_FILE:-${WORK_DIR}/normalised-results.json}"
FAIL_ON_NO_RESULTS="${FAIL_ON_NO_RESULTS:-true}"

# Field and record separators. ASCII unit/record separators are used instead of
# tabs or newlines because JUnit failure bodies routinely contain both.
FS=$'\x1f'
RS=$'\x1e'

# ---------------------------------------------------------------------------
# Resolve input globs to a concrete file list
# ---------------------------------------------------------------------------
shopt -s nullglob
shopt -s globstar 2>/dev/null || tom-echo-yellow "bash lacks globstar; '**' will not recurse."

files=()
while IFS= read -r pattern; do
  [ -n "$pattern" ] || continue
  # Unquoted on purpose: this is where the caller's glob gets expanded.
  # shellcheck disable=SC2206
  matches=($pattern)
  if [ ${#matches[@]} -eq 0 ]; then
    tom-echo-yellow "No files matched pattern: ${pattern}"
    continue
  fi
  for match in "${matches[@]}"; do
    [ -f "$match" ] && files+=("$match")
  done
done < <(printf '%s\n' "$JUNIT_PATHS" | tr ' ' '\n')

if [ ${#files[@]} -eq 0 ]; then
  if [ "$FAIL_ON_NO_RESULTS" = "true" ]; then
    die "No JUnit XML files matched JUNIT_PATHS: ${JUNIT_PATHS}"
  fi
  tom-echo-yellow "No JUnit XML files matched JUNIT_PATHS: ${JUNIT_PATHS}"
fi

tom-echo "Collecting ${#files[@]} JUnit file(s)"
for file in "${files[@]+"${files[@]}"}"; do
  tom-echo "  ${file}"
done

# ---------------------------------------------------------------------------
# Extract every <testcase> into JSON Lines
# ---------------------------------------------------------------------------
cases_jsonl="${WORK_DIR}/cases.jsonl"
: >"$cases_jsonl"

extract_cases() {
  # Emits one record per testcase, fields separated by FS, records by RS.
  # name(...) on a node-set returns the name of the first node, which is how
  # the outcome element (failure/error/skipped) is identified.
  xmlstarlet sel -t -m '//testcase' \
    -v 'string((ancestor::testsuite/@name)[last()])' -o "$FS" \
    -v 'string(@classname)' -o "$FS" \
    -v 'string(@name)' -o "$FS" \
    -v 'string(@time)' -o "$FS" \
    -v 'name((failure|error|skipped)[1])' -o "$FS" \
    -v 'string((failure|error|skipped)[1]/@message)' -o "$FS" \
    -v 'string((failure|error|skipped)[1])' -o "$RS" \
    "$1"
}

for file in "${files[@]+"${files[@]}"}"; do
  if ! xmlstarlet val -q -w "$file"; then
    die "Not well-formed XML: ${file}"
  fi

  while IFS= read -r -d "$RS" record; do
    [ -n "${record//[[:space:]]/}" ] || continue

    # read -d '' keeps embedded newlines inside fields; only FS splits fields.
    IFS="$FS" read -r -d '' suite classname case_name duration outcome message details \
      < <(printf '%s\0' "$record") || true

    case "$outcome" in
      failure) status="FAILED" ;;
      error)   status="ERROR" ;;
      skipped) status="SKIPPED" ;;
      "")      status="PASSED" ;;
      *)       status="UNKNOWN" ;;
    esac

    jq -nc \
      --arg source_file "$file" \
      --arg suite "$suite" \
      --arg classname "$classname" \
      --arg name "$case_name" \
      --arg duration "$duration" \
      --arg status "$status" \
      --arg message "$message" \
      --arg details "$details" \
      '{
        source_file: $source_file,
        suite: $suite,
        classname: $classname,
        name: $name,
        duration: (($duration | tonumber?) // 0),
        status: $status,
        message: ($message | sub("^\\s+";"") | sub("\\s+$";"")),
        details: ($details | sub("^\\s+";"") | sub("\\s+$";""))
      }' >>"$cases_jsonl"
  done < <(extract_cases "$file")
done

# ---------------------------------------------------------------------------
# Aggregate into the normalised document
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$OUTPUT_FILE")"

source_files_json=$(printf '%s\n' "${files[@]+"${files[@]}"}" | jq -R . | jq -sc 'map(select(length > 0))')

jq -s \
  --arg collected_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --argjson source_files "$source_files_json" \
  '{
    schema: "junit-normalised/v1",
    collected_at: $collected_at,
    source_files: $source_files,
    totals: {
      tests:   length,
      passed:  map(select(.status == "PASSED"))  | length,
      failed:  map(select(.status == "FAILED"))  | length,
      errors:  map(select(.status == "ERROR"))   | length,
      skipped: map(select(.status == "SKIPPED")) | length,
      duration: (map(.duration) | add // 0)
    },
    suites: (
      group_by(.suite)
      | map({
          name: .[0].suite,
          duration: (map(.duration) | add // 0),
          cases: map(del(.suite))
        })
    )
  }' "$cases_jsonl" >"$OUTPUT_FILE"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
read -r total passed failed errors skipped < <(
  jq -r '.totals | "\(.tests) \(.passed) \(.failed) \(.errors) \(.skipped)"' "$OUTPUT_FILE"
)

tom-echo "COLLECTED TEST RESULTS"
tom-echo "  Files:   ${#files[@]}"
tom-echo "  Tests:   ${total}"
tom-echo "  Passed:  ${passed}"
tom-echo "  Failed:  ${failed}"
tom-echo "  Errors:  ${errors}"
tom-echo "  Skipped: ${skipped}"
tom-echo "  Output:  ${OUTPUT_FILE}"

if [ "$total" -eq 0 ] && [ "$FAIL_ON_NO_RESULTS" = "true" ]; then
  die "No test cases found in the matched JUnit files."
fi

set_output normalised_file "$OUTPUT_FILE"
set_output total_tests "$total"
set_output passed "$passed"
set_output failed "$failed"
set_output errors "$errors"
set_output skipped "$skipped"
