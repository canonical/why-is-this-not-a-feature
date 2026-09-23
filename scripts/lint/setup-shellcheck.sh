#!/usr/bin/env bash
source "$(dirname "$0")/../_util.sh"

# Install shellcheck for shell script linting
# Usage: ./scripts/lint/setup-shellcheck.sh

if command -v shellcheck &>/dev/null; then
    tom-echo "shellcheck is already installed. Skipping."
    exit 0
fi

tom-echo "Installing shellcheck via snap..."
retry sudo snap install shellcheck

tom-echo "shellcheck setup complete."
