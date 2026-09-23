#!/usr/bin/env bash
source "$(dirname "$0")/../_util.sh"

# Run shellcheck on all shell scripts
# Usage: ./scripts/lint/shell.sh

require shellcheck

tom-echo "Running shellcheck on all shell scripts..."
find . -name '*.sh' -print0 | xargs -0 shellcheck -x -e SC1091,SC2001,SC2129

tom-echo "All checks passed."
