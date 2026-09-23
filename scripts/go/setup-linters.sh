#!/usr/bin/env bash
source "$(dirname "$0")/../_util.sh"

# Install golangci-lint for Go linting
# Usage: ./scripts/go/setup-linters.sh
# GOLANGCI_LINT_VERSION is pinned in scripts/_util.sh.

require go "Go is not installed. Run ./scripts/go/setup.sh first."

tom-echo "Checking for golangci-lint installation..."

if command -v golangci-lint &>/dev/null; then
    INSTALLED_VERSION=$(golangci-lint --version 2>&1 | grep -oP 'version \K[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    tom-echo "golangci-lint is already installed: v${INSTALLED_VERSION}"

    if [[ "v${INSTALLED_VERSION}" == "$GOLANGCI_LINT_VERSION" ]]; then
        tom-echo "golangci-lint ${GOLANGCI_LINT_VERSION} is already installed. Skipping."
        exit 0
    else
        tom-echo-yellow "Installed golangci-lint version v${INSTALLED_VERSION} differs from ${GOLANGCI_LINT_VERSION}"
        tom-echo-yellow "Reinstalling to match pinned version..."
    fi
fi

tom-echo "Installing golangci-lint ${GOLANGCI_LINT_VERSION} via go install..."
# Force using the current Go toolchain, don't auto-switch to older versions
retry env GOTOOLCHAIN=local go install "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@${GOLANGCI_LINT_VERSION}"

# Ensure GOPATH/bin or GOBIN is in PATH
GOBIN="${GOBIN:-$(go env GOPATH)/bin}"
if [[ ":$PATH:" != *":$GOBIN:"* ]]; then
    tom-echo-yellow "WARNING: $GOBIN is not in your PATH."
    tom-echo-yellow "Add this to your ~/.bashrc or ~/.zshrc:"
    tom-echo-yellow "  export PATH=\"\$PATH:$GOBIN\""
fi
# Make it available to later workflow steps, which run in a fresh shell.
if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$GOBIN" >> "$GITHUB_PATH"
fi

tom-echo "Verifying golangci-lint installation..."
"$GOBIN/golangci-lint" --version

tom-echo "golangci-lint setup complete."
