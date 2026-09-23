#!/usr/bin/env bash
source "$(dirname "$0")/../_util.sh"

# Install Go via snap at the version pinned in go.mod (major.minor track).
# All install and version-resolution logic lives in `requires`/_util.sh
# (GO_CHANNEL overrides the go.mod-derived channel).
# Usage: ./scripts/go/setup.sh

# Prefer the snap toolchain over any Go preinstalled on the runner. A
# non-existent /snap/bin (e.g. on macOS) is harmless on PATH.
export PATH="/snap/bin:$PATH"
hash -r 2>/dev/null || true

require go

# Pin the toolchain so Go does not silently download a different one.
export GOTOOLCHAIN=local

# Later workflow steps run in a fresh shell. GITHUB_PATH entries are prepended,
# which is what keeps snap Go ahead of the preinstalled toolchain.
if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "/snap/bin" >> "$GITHUB_PATH"
fi
if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "GOTOOLCHAIN=local" >> "$GITHUB_ENV"
fi

tom-echo "Using $(command -v go): $(go version)"
