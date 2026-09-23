#!/usr/bin/env bash
source "$(dirname "$0")/../_util.sh"

# Run action-validator and zizmor on GitHub Actions workflow files
# Usage: ./scripts/lint/actions.sh

require action-validator
require zizmor

tom-echo "Validating GitHub Actions workflows with action-validator..."
for f in .github/workflows/*.yml; do
    action-validator "$f"
done

# This repo's product is composite actions, so validate their definitions too.
if [[ -d .github/actions ]]; then
    tom-echo "Validating composite actions with action-validator..."
    while IFS= read -r -d '' f; do
        action-validator "$f"
    done < <(find .github/actions \( -name 'action.yml' -o -name 'action.yaml' \) -print0)
fi

tom-echo "Scanning GitHub Actions workflows with zizmor..."
if [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    zizmor .github/workflows/
else
    tom-echo-yellow "No GH_TOKEN set, running zizmor in offline mode (skipping network checks)."
    zizmor --offline .github/workflows/
fi

tom-echo "All workflow checks passed."
