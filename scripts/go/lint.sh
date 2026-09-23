#!/usr/bin/env bash
source "$(dirname "$0")/../_util.sh"

# Run Go linting, formatting checks, and module verification
# Usage: ./scripts/go/lint.sh
#
# This repo keeps its Go programs in per-action subdirectories, each its own
# module, so the module-scoped checks run once per discovered go.mod.

require go "Go is not installed. Run ./scripts/go/setup.sh first."

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || die "Could not enter repo root: ${REPO_ROOT}"

# Determine golangci-lint path
GOBIN="${GOBIN:-$(go env GOPATH)/bin}"
GOLANGCI_LINT="${GOBIN}/golangci-lint"

if ! command -v golangci-lint &>/dev/null && [[ ! -x "$GOLANGCI_LINT" ]]; then
    tom-echo-red "golangci-lint is not installed. Run ./scripts/go/setup-linters.sh first."
    exit 1
fi

# Use golangci-lint from GOBIN if not in PATH
if command -v golangci-lint &>/dev/null; then
    GOLANGCI_LINT_BIN="golangci-lint"
else
    GOLANGCI_LINT_BIN="$GOLANGCI_LINT"
    tom-echo "Using golangci-lint from $GOLANGCI_LINT"
fi

tom-echo "Running Go formatting check (gofmt)..."
UNFORMATTED=$(gofmt -l .)
if [[ -n "$UNFORMATTED" ]]; then
    tom-echo-red "The following files are not formatted:"
    echo "$UNFORMATTED"
    tom-echo-red "Run 'gofmt -w .' to auto-fix formatting."
    exit 1
fi
tom-echo "All Go files are properly formatted."

# Module-scoped checks: go vet, go mod verify, tidiness, golangci-lint.
check_module() {
    local mod="$1"
    tom-echo "--- Module: ${mod} ---"
    pushd "$mod" >/dev/null || die "Could not enter module directory: ${mod}"

    tom-echo "Running go vet..."
    go vet -tags integration ./...

    tom-echo "Verifying go.mod and go.sum..."
    go mod verify

    tom-echo "Checking if go.mod and go.sum are tidy..."
    # Save current state
    cp go.mod go.mod.before
    if [[ -f go.sum ]]; then
        cp go.sum go.sum.before
    fi
    # Run tidy
    go mod tidy
    # Check if anything changed
    if ! diff -q go.mod go.mod.before >/dev/null 2>&1; then
        tom-echo-red "go.mod in ${mod} is not tidy."
        tom-echo-red "Run 'go mod tidy' to auto-fix."
        # Restore original state
        mv go.mod.before go.mod
        [[ -f go.sum.before ]] && mv go.sum.before go.sum
        exit 1
    fi
    if [[ -f go.sum ]] && [[ -f go.sum.before ]] && ! diff -q go.sum go.sum.before >/dev/null 2>&1; then
        tom-echo-red "go.sum in ${mod} is not tidy."
        tom-echo-red "Run 'go mod tidy' to auto-fix."
        # Restore original state
        mv go.mod.before go.mod
        mv go.sum.before go.sum
        exit 1
    fi
    # Clean up temp files
    rm -f go.mod.before go.sum.before
    tom-echo "go.mod and go.sum are tidy."

    tom-echo "Running golangci-lint..."
    "$GOLANGCI_LINT_BIN" run --build-tags integration --timeout=5m

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
    check_module "$mod"
done

tom-echo "All Go checks passed."
