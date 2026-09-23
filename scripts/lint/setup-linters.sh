#!/usr/bin/env bash
source "$(dirname "$0")/../_util.sh"

# Install action-validator and zizmor for GitHub Actions linting
# Usage: ./scripts/lint/setup-linters.sh
# Versions are pinned in scripts/_util.sh.

tom-echo "Installing action-validator v${ACTION_VALIDATOR_VERSION}..."
retry curl -sL "https://github.com/mpalmer/action-validator/releases/download/v${ACTION_VALIDATOR_VERSION}/action-validator_linux_amd64" -o action-validator
echo "${ACTION_VALIDATOR_SHA256}  action-validator" | sha256sum --check --strict
chmod +x action-validator
sudo mv action-validator /usr/local/bin/

tom-echo "Installing zizmor v${ZIZMOR_VERSION}..."
retry sudo apt-get update -qq
retry sudo apt-get install -qq -y pipx
retry pipx install "zizmor==${ZIZMOR_VERSION}"
# Add pipx bin directory to PATH for the current shell
export PATH="$HOME/.local/bin:$PATH"
# ...and for later workflow steps, which run in a fresh shell.
if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$HOME/.local/bin" >> "$GITHUB_PATH"
fi

tom-echo "Linter setup complete."
