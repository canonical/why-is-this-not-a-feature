#!/usr/bin/env bash
source "$(dirname "$0")/../_util.sh"

# Run Go tests with race detection and coverage.
# Usage: ./scripts/go/test.sh [--integration]
#
# --integration   Also run integration tests (always enabled in CI).
#
# This repo keeps its Go programs in per-action subdirectories, each its own
# module, so tests run once per discovered go.mod and their reports land in
# coverage/<module>/.

require go "Go is not installed. Run ./scripts/go/setup.sh first."

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || die "Could not enter repo root: ${REPO_ROOT}"

# Integration tests are always on in CI; locally opt in with --integration.
RUN_INTEGRATION=false
if [[ "${GITHUB_ACTIONS:-}" == "true" ]] || [[ "${1:-}" == "--integration" ]]; then
  RUN_INTEGRATION=true
fi

# Determine output format (github-actions in CI, standard-verbose locally)
GOTESTSUM_FORMAT="${GOTESTSUM_FORMAT:-$(if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then echo "github-actions"; else echo "standard-verbose"; fi)}"

BUILD_TAGS=()
if [[ "$RUN_INTEGRATION" == "true" ]]; then
  BUILD_TAGS=(-tags integration)
  tom-echo "Running Go unit + integration tests with race detection and coverage..."
else
  tom-echo "Running Go unit tests with race detection and coverage..."
  tom-echo "(Pass --integration to also run integration tests)"
fi

COVERAGE_DIR="${REPO_ROOT}/coverage"
rm -rf "$COVERAGE_DIR"
mkdir -p "$COVERAGE_DIR"

test_module() {
    local mod="$1"
    local out_dir
    out_dir="${COVERAGE_DIR}/$(basename "$mod")"
    mkdir -p "$out_dir"

    tom-echo "--- Module: ${mod} ---"
    pushd "$mod" >/dev/null || die "Could not enter module directory: ${mod}"

    # Note: expanding an *unset* array with "${BUILD_TAGS[@]}" under set -u can fail (bash <4.4 quirk).
    # The ${var+"$var"} idiom expands to nothing when the variable is unset, avoiding the error.
    go run gotest.tools/gotestsum@latest \
      --format "$GOTESTSUM_FORMAT" \
      -- \
      -race \
      -coverpkg=./... \
      -coverprofile=coverage-go.out \
      -covermode=atomic \
      ${BUILD_TAGS[@]+"${BUILD_TAGS[@]}"} \
      ./...

    # A module with no _test.go files produces no profile; that is not a failure.
    if [[ -s coverage-go.out ]]; then
        tom-echo "Generating HTML coverage report..."
        # Generated from inside the module so `go tool cover` can resolve sources.
        go tool cover -html=coverage-go.out -o coverage-go.html
        tom-echo "Coverage summary:"
        go tool cover -func=coverage-go.out
        mv coverage-go.out coverage-go.html "$out_dir/"
    else
        tom-echo-yellow "No coverage produced for ${mod} (no test files)."
        rm -f coverage-go.out
    fi

    popd >/dev/null || die "Could not return from module directory: ${mod}"
}

modules=()
while IFS= read -r gomod; do
    modules+=("$(dirname "$gomod")")
done < <(find . -name go.mod -not -path '*/vendor/*' | sort)

if [[ ${#modules[@]} -eq 0 ]]; then
    die "No Go modules found under ${REPO_ROOT}."
fi

tom-echo "Found ${#modules[@]} Go module(s)."
for mod in "${modules[@]}"; do
    test_module "$mod"
done

tom-echo "Go tests complete. Coverage reports: ${COVERAGE_DIR}/"
