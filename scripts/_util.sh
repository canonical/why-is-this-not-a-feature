#!/usr/bin/env bash

# _util.sh - Common utilities for scripts
# This file can be sourced by any other script

# Strict error handling
# -e: Exit on error
# -u: Exit on undefined variable
# -o pipefail: Exit on pipe failure
set -euo pipefail

# ANSI color codes
export GREY='\033[0;90m'
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Pinned snap channels (single source of truth)
#
# Keep build tooling reproducible across CI and local VMs. Each value can be
# overridden by exporting the matching variable before invoking a script.
# Note: rockcraft only publishes the `latest` track, so `latest/stable` is the
# most specific channel available for it.
# ---------------------------------------------------------------------------
export CHARMCRAFT_CHANNEL="${CHARMCRAFT_CHANNEL:-3.x/stable}"
export ROCKCRAFT_CHANNEL="${ROCKCRAFT_CHANNEL:-latest/stable}"
export LXD_CHANNEL="${LXD_CHANNEL:-5.21/stable}"

# ---------------------------------------------------------------------------
# Pinned apt package versions (single source of truth)
#
# apt version strings are Ubuntu-release specific (jq is 1.7.1-3build1 on
# noble but 1.6-2.1ubuntu3 on jammy), so pinning here would break the moment a
# runner image changes. These default to empty, meaning "whatever the runner's
# archive provides"; set them to freeze a version once the runner image is
# itself pinned.
# ---------------------------------------------------------------------------
export JQ_APT_VERSION="${JQ_APT_VERSION:-}"
export XMLSTARLET_APT_VERSION="${XMLSTARLET_APT_VERSION:-}"
export CURL_APT_VERSION="${CURL_APT_VERSION:-}"

# Error trap handler - identifies the failed command, exit code, and source location
error_trap() {
    local exit_code=$?
    local line_number=${1:-0}
    # Get the script name safely, checking if BASH_SOURCE has enough elements.
    # Use _script_label for the full repo-relative path (not just the basename).
    local script_name="unknown"
    if [ ${#BASH_SOURCE[@]} -gt 1 ]; then
        script_name=$(_script_label "${BASH_SOURCE[1]}")
    fi
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    local failed_command="${BASH_COMMAND}"

    local message="Exit code ${exit_code} returned from command: '${failed_command}'"
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::error::[${timestamp}][${script_name}:${line_number}] - ${message}" >&2
    else
        # Format: [HH:mm:ss][script.sh:lineNumber] - ERROR: message
        echo -e "${GREY}[${timestamp}][${script_name}:${line_number}]${NC} - ${RED}ERROR:${NC} ${message}" >&2
    fi
    exit $exit_code
}

# Set up error trap for any script that sources this file.  Any uncaught error will trigger this trap.
trap 'error_trap $LINENO' ERR

# Resolve a caller's BASH_SOURCE path to a stable, repo-relative label for logs.
# Tolerant of the working directory having changed since the script started:
# relative BASH_SOURCE paths would otherwise fail to resolve after a `cd`.
_script_label() {
    local src="$1" dir name
    dir=$(cd "$(dirname "$src")" 2>/dev/null && pwd) || dir=$(dirname "$src")
    name="${dir}/$(basename "$src")"
    name="${name#"$PWD"/}"
    printf '%s' "$name" | sed -E 's|.*/(scripts/.*)$|\1|'
}

die () {
    local message="$*"
    local timestamp
    timestamp=$(date '+%H:%M:%S')

    # Get the caller information
    local caller_info="${BASH_SOURCE[1]}"
    local line_number="${BASH_LINENO[0]}"

    local script_name
    script_name=$(_script_label "$caller_info")

    # Format: [HH:mm:ss][script.sh:lineNumber] - message
    echo -e "${GREY}[${timestamp}][${script_name}:${line_number}]${NC} - ${RED}ERROR:${NC} ${message}" >&2
    exit 1
}

# Warning echo function with timestamp and source location (yellow).
# In GitHub Actions, also emits a `::warning::` workflow annotation so it shows
# up in the run summary; locally it prints colored output to stderr.
# Usage: tom-echo-yellow "Your warning here"   (alias: tom-echo-warning)
tom-echo-yellow() {
    local message="$*"
    local timestamp
    timestamp=$(date '+%H:%M:%S')

    # Get the caller information
    local caller_info="${BASH_SOURCE[1]}"
    local line_number="${BASH_LINENO[0]}"

    local script_name
    script_name=$(_script_label "$caller_info")

    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::warning::[${timestamp}][${script_name}:${line_number}] - ${message}" >&2
    else
        # Format: [HH:mm:ss][script.sh:lineNumber] - WARNING: message
        echo -e "${GREY}[${timestamp}][${script_name}:${line_number}]${NC} - ${YELLOW}WARNING:${NC} ${message}" >&2
    fi
}
# Alias for cross-repo parity.
tom-echo-warning() { tom-echo-yellow "$@"; }

# Error echo function with timestamp and source location (red).
# In GitHub Actions, also emits a `::error::` workflow annotation; locally it
# prints colored output to stderr.
# Usage: tom-echo-red "Your error here"   (alias: tom-echo-error)
tom-echo-red() {
    local message="$*"
    local timestamp
    timestamp=$(date '+%H:%M:%S')

    # Get the caller information
    local caller_info="${BASH_SOURCE[1]}"
    local line_number="${BASH_LINENO[0]}"

    local script_name
    script_name=$(_script_label "$caller_info")

    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "::error::[${timestamp}][${script_name}:${line_number}] - ${message}" >&2
    else
        # Format: [HH:mm:ss][script.sh:lineNumber] - ERROR: message
        echo -e "${GREY}[${timestamp}][${script_name}:${line_number}]${NC} - ${RED}ERROR:${NC} ${message}" >&2
    fi
}
# Alias for cross-repo parity.
tom-echo-error() { tom-echo-red "$@"; }

# Custom echo function with timestamp and source location.
# Writes to stderr so it never contaminates a script's stdout (which may be
# captured via command substitution or used for real data output).
# Usage: tom-echo "Your message here"
tom-echo() {
    local message="$*"
    local timestamp
    timestamp=$(date '+%H:%M:%S')

    # Get the caller information
    local caller_info="${BASH_SOURCE[1]}"
    local line_number="${BASH_LINENO[0]}"

    local script_name
    script_name=$(_script_label "$caller_info")

    # Format: [HH:mm:ss][script.sh:lineNumber] - message
    echo -e "${GREY}[${timestamp}][${script_name}:${line_number}]${NC} - ${message}" >&2
}

# Require a command to be available. Attempts a CI auto-install first (see
# `requires`); dies with an optional custom message if still missing.
# Usage: require <command> [message]
# `require` is kept as an alias of `requires` for backward compatibility.
require() { requires "$@"; }

# Skip the script gracefully if a command is missing.
# Usage: skip_if_missing <command> [message]
skip_if_missing() {
    local cmd="${1:?Usage: skip_if_missing <command> [message]}"
    local msg="${2:-${cmd} not installed, skipping.}"
    if ! command -v "$cmd" &>/dev/null; then
        local timestamp
        timestamp=$(date '+%H:%M:%S')
        local script_name
        script_name=$(_script_label "${BASH_SOURCE[1]}")
        local line_number="${BASH_LINENO[0]}"
        echo -e "${GREY}[${timestamp}][${script_name}:${line_number}]${NC} - ${YELLOW}WARNING:${NC} ${msg}" >&2
        exit 0
    fi
}

# Skip the script gracefully when a boolean flag env var is set to "true".
# Complements skip_if_missing (which checks for a command); this checks a value.
# Usage: skip_if <VAR_NAME>
skip_if() {
    local var="${1:?Usage: skip_if <VAR_NAME>}"
    if [[ "${!var:-}" == "true" ]]; then
        local timestamp
        timestamp=$(date '+%H:%M:%S')
        local script_name
        script_name=$(_script_label "${BASH_SOURCE[1]}")
        local line_number="${BASH_LINENO[0]}"
        echo -e "${GREY}[${timestamp}][${script_name}:${line_number}]${NC} - ${YELLOW}Skipping due to:${NC} ${var}=true" >&2
        exit 0
    fi
}

# Die unless every named environment variable is set and non-empty. The env-var
# counterpart to `requires`, for scripts whose inputs arrive as environment.
# Usage: require_env VAR1 VAR2 ...
require_env() {
    local name timestamp script_name line_number message
    for name in "$@"; do
        if [ -z "${!name:-}" ]; then
            timestamp=$(date '+%H:%M:%S')
            # Report the caller's location, not this function's.
            script_name=$(_script_label "${BASH_SOURCE[1]}")
            line_number="${BASH_LINENO[0]}"
            message="Required environment variable ${name} is not set."
            if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
                echo "::error::[${timestamp}][${script_name}:${line_number}] - ${message}" >&2
            else
                echo -e "${GREY}[${timestamp}][${script_name}:${line_number}]${NC} - ${RED}ERROR:${NC} ${message}" >&2
            fi
            exit 1
        fi
    done
}

# Write a GitHub Actions step output. No-op outside Actions, so the same script
# runs unchanged locally.
# Usage: set_output <key> <value>
set_output() {
    local key="${1:?Usage: set_output <key> <value>}"
    local value="${2-}"
    [ -n "${GITHUB_OUTPUT:-}" ] || return 0
    {
        printf '%s<<__GHA_EOF__\n' "$key"
        printf '%s\n' "$value"
        printf '__GHA_EOF__\n'
    } >>"$GITHUB_OUTPUT"
}

# Print (creating on demand) a scratch directory for intermediate artifacts.
# Prefers RUNNER_TEMP so GitHub Actions cleans up after the job.
# Usage: work_dir <name>
work_dir() {
    local name="${1:?Usage: work_dir <name>}"
    local dir="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/${name}"
    mkdir -p "$dir"
    printf '%s' "$dir"
}

# Dump selected environment variables (and cwd) for debugging. Output goes to
# stderr so it never contaminates a script's stdout.
# WARNING: prints values verbatim -- never pass secret-bearing var names when
# the output may end up in shared logs (e.g. CHARMCRAFT_AUTH, tokens).
# Usage: dump_env VAR1 VAR2 ...
dump_env() {
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    local script_name
    script_name=$(_script_label "${BASH_SOURCE[1]}")
    local line_number="${BASH_LINENO[0]}"

    echo -e "${GREY}[${timestamp}][${script_name}:${line_number}]${NC} - ${CYAN}dump_env called with: $*${NC}" >&2
    echo -e "${CYAN}--- START ENV DUMP ---${NC}" >&2
    echo -e "${CYAN}working directory: $(pwd)${NC}" >&2
    for var in "$@"; do
        if [ -n "${!var+x}" ]; then
            echo -e "${CYAN}export ${var}=${!var}${NC}" >&2
        fi
    done
    echo -e "${CYAN}--- END ENV DUMP ---${NC}" >&2
}

# Retry a command with exponential backoff, for transient network failures
# (apt/snap/pip installs, curl, registry login/pull/push, etc.).
#
# Returns 0 on success, or the last failure's exit code after exhausting all
# attempts. It does NOT exit the script itself, so it composes with `if`, `&&`
# and `||`; under `set -e` an unguarded failed retry still aborts as usual.
# Diagnostic messages go to stderr so they survive stdout redirection.
#
# Usage: retry <command> [args...]
#   Wrap env-prefixed commands with `env`, e.g. `retry env FOO=bar mytool`.
# Configurable via environment:
#   RETRY_MAX_ATTEMPTS - total attempts before giving up (default: 5)
#   RETRY_BASE_DELAY   - initial backoff seconds, doubled each retry (default: 2)
retry() {
    local max_attempts="${RETRY_MAX_ATTEMPTS:-5}"
    local delay="${RETRY_BASE_DELAY:-2}"
    local attempt=1
    local exit_code=0

    while true; do
        exit_code=0
        "$@" || exit_code=$?
        if (( exit_code == 0 )); then
            return 0
        fi
        if (( attempt >= max_attempts )); then
            tom-echo-red "Command failed after ${max_attempts} attempts (exit ${exit_code}): $*" >&2
            return "$exit_code"
        fi
        tom-echo-yellow "Command failed (exit ${exit_code}); attempt ${attempt}/${max_attempts}, retrying in ${delay}s: $*" >&2
        sleep "$delay"
        delay=$(( delay * 2 ))
        attempt=$(( attempt + 1 ))
    done
}

# Sets common registry/image variables. Call explicitly in scripts that need them.
# All variables are overridable via environment.
init_registry_vars() {
    REGISTRY="${REGISTRY:-ghcr.io}"
    IMAGE_NAME="${IMAGE_NAME:-$(git remote get-url origin | sed -E 's|.*github\.com[:/]||;s|\.git$||' | tr '[:upper:]' '[:lower:]')}"
    ARCH="${ARCH:-$(uname -m | sed 's/aarch64/arm64/' | sed 's/x86_64/amd64/')}"
}

# Resolve the available skopeo binary (rockcraft.skopeo or skopeo).
# Sets SKOPEO variable. Dies if neither is found.
# shellcheck disable=SC2034
resolve_skopeo() {
    if command -v rockcraft.skopeo &>/dev/null; then
        SKOPEO=rockcraft.skopeo
    elif command -v skopeo &>/dev/null; then
        SKOPEO=skopeo
    else
        die "skopeo not found. Install it or use the rockcraft snap."
    fi
}

# Internal: perform a single registry-login attempt. Separated out so it can be
# wrapped by `retry` (the token must be re-piped to stdin on every attempt).
# Usage: _registry_login_attempt <tool>
_registry_login_attempt() {
    local tool="$1"
    echo "$REGISTRY_TOKEN" | "$tool" login "$REGISTRY" -u "$REGISTRY_USER" --password-stdin
}

# Log in to a container registry. Requires REGISTRY_USER and REGISTRY_TOKEN.
# Usage: registry_login <tool> (where tool is "docker" or a skopeo binary path)
# For docker: uses a temporary config dir to avoid credential helpers stealing focus.
registry_login() {
    local tool="${1:?Usage: registry_login <tool>}"
    if [[ -n "${REGISTRY_TOKEN:-}" && -n "${REGISTRY_USER:-}" ]]; then
        tom-echo "Logging in to ${REGISTRY}..."
        if [[ "$tool" == "docker" ]]; then
            # Use a temp config to bypass the desktop credential helper (avoids focus steal)
            DOCKER_CONFIG="$(mktemp -d)"
            export DOCKER_CONFIG
            trap 'rm -rf "$DOCKER_CONFIG"' EXIT
        fi
        retry _registry_login_attempt "$tool"
    else
        die "Please set REGISTRY_USER and REGISTRY_TOKEN environment variables to push or pull from ${REGISTRY}."
    fi
}

# Generate container image tags from git state
# Usage: generate_image_tags <type> <arch>
#   type: "docker" or "rock"
#   arch: "amd64" or "arm64"
# Outputs multiple tags (one per line):
#   <datetime>-<commit>-<arch>-<type>  (immutable, always)
#   latest-<arch>-<type>               (mutable, main branch only)
generate_image_tags() {
    local type="${1:?Usage: generate_image_tags <type> <arch>}"
    local arch="${2:?Usage: generate_image_tags <type> <arch>}"
    local branch="${GITHUB_REF_NAME:-${GITHUB_HEAD_REF:-$(git symbolic-ref --quiet --short HEAD 2>/dev/null || git name-rev --name-only HEAD 2>/dev/null | sed 's|.*/||' || echo "unknown")}}"
    local commit_hash
    commit_hash=$(git rev-parse --short HEAD 2>/dev/null | tr '[:upper:]' '[:lower:]')
    local datetime
    datetime="$(date -u '+%Y%m%dT%H%M%SZ')"

    # Always push the immutable timestamped tag
    echo "${datetime}-${commit_hash}-${arch}-${type}"

    # Push latest tag only on main
    if [[ "$branch" == "main" ]]; then
        echo "latest-${arch}-${type}"
    fi
}

# ---------------------------------------------------------------------------
# CI auto-install support
# ---------------------------------------------------------------------------
# Bash 3-compatible command -> installer lookup (no associative arrays).
# charmcraft/rockcraft/lxd are absent on purpose -- concierge provisions them.
_install_map_lookup() {
    local cmd="$1"
    case "$cmd" in
        curl)        echo "_install_apt curl ${CURL_APT_VERSION}" ;;
        jq)          echo "_install_apt jq ${JQ_APT_VERSION}" ;;
        xmlstarlet)  echo "_install_apt xmlstarlet ${XMLSTARLET_APT_VERSION}" ;;
        rsync)       echo "_install_apt rsync" ;;
        yq)          echo "_install_snap yq" ;;
        go)          echo "_install_go" ;;
        *)           echo "" ;;
    esac
}

_install_apt() {
    local pkg="$1"
    local version="${2:-}"
    tom-echo "Installing '${pkg}' via apt..."
    retry sudo apt-get update -qq
    if [[ -n "$version" ]]; then
        retry sudo apt-get install -y -qq "${pkg}=${version}"
    else
        retry sudo apt-get install -y -qq "$pkg"
    fi
}

_install_snap() {
    local pkg="$1"
    shift
    local channel=""
    local args=()
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--channel" ]]; then
            channel="$2"
            shift 2
        else
            args+=("$1")
            shift
        fi
    done
    tom-echo "Installing '${pkg}' via snap..."
    if [[ -n "$channel" ]]; then
        retry sudo snap install "$pkg" --channel="$channel" "${args[@]}"
    else
        retry sudo snap install "$pkg" "${args[@]}"
    fi
}

# Walk up to find go.mod so callers work from any subdirectory.
_find_gomod() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/go.mod" ]]; then
            printf '%s\n' "$dir/go.mod"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Pin Go to the same major.minor as go.mod so the toolchain matches the module
# (GO_CHANNEL overrides).
_go_channel() {
    if [[ -n "${GO_CHANNEL:-}" ]]; then
        printf '%s\n' "$GO_CHANNEL"
        return 0
    fi
    local gomod version
    gomod="$(_find_gomod)" || { echo ""; return 0; }
    # `|| true`: a no-match grep must not trip `pipefail` and abort the script.
    version=$(grep '^go ' "$gomod" | awk '{print $2}' | cut -d. -f1,2 || true)
    [[ -n "$version" ]] && printf '%s/stable\n' "$version" || echo ""
}

# Install Go at the go.mod-pinned channel (replaces scripts/go/setup.sh).
_install_go() {
    local channel
    channel="$(_go_channel)"
    [[ -z "$channel" ]] && die "Could not determine the Go version from go.mod (set GO_CHANNEL to override)."
    _install_snap go --classic --channel "$channel"
}

# Craft tools provisioned by concierge, not by direct snap install.
_concierge_managed() {
    case "$1" in
        charmcraft|rockcraft|lxd) return 0 ;;
        *)                        return 1 ;;
    esac
}

# Snap's tracked channel for a tool, or empty if not a snap. Uses `snap info`
# because `snap list` truncates its Tracking column when piped.
_installed_channel() {
    snap info "$1" 2>/dev/null | awk '/^tracking:/ {print $2; exit}' || true
}

# True unless the tool needs (re)provisioning: missing, not a snap (e.g. the
# lxd-installer shim), or on the wrong channel. Unpinned tools are always fine.
_pinned_channel_ok() {
    local tool="$1" expected have
    expected="$(_pinned_channel "$tool")"
    [[ -z "$expected" ]] && return 0
    have="$(_installed_channel "$tool")"
    [[ -n "$have" && "$have" == "$expected" ]]
}

# Provision charmcraft/rockcraft/lxd in one idempotent concierge run rather than
# installing each snap separately; channels are pinned via CONCIERGE_*_CHANNEL.
_prepare_with_concierge() {
    if ! command -v concierge &>/dev/null; then
        tom-echo "Installing concierge..."
        retry sudo snap install --classic concierge
        hash -r 2>/dev/null || true
    fi
    tom-echo "Provisioning craft tools via concierge (crafts preset)..."
    retry sudo env \
        CONCIERGE_CHARMCRAFT_CHANNEL="$CHARMCRAFT_CHANNEL" \
        CONCIERGE_ROCKCRAFT_CHANNEL="$ROCKCRAFT_CHANNEL" \
        CONCIERGE_LXD_CHANNEL="$LXD_CHANNEL" \
        concierge prepare -p crafts
}

# Pinned channel for a tool, or empty if unpinned.
_pinned_channel() {
    case "$1" in
        go)         _go_channel ;;
        charmcraft) printf '%s\n' "$CHARMCRAFT_CHANNEL" ;;
        rockcraft)  printf '%s\n' "$ROCKCRAFT_CHANNEL" ;;
        lxd)        printf '%s\n' "$LXD_CHANNEL" ;;
        *)          echo "" ;;
    esac
}

# Warn (don't fail) when an installed pinned tool drifts from its expected
# version, so builds surface the mismatch instead of silently using the wrong
# toolchain.
_check_pinned_version() {
    local tool="$1" expected tracking
    expected="$(_pinned_channel "$tool")"
    [[ -z "$expected" ]] && return 0

    if [[ "$tool" == "go" ]]; then
        local want have
        want="${expected%%/*}"
        # `|| true`: don't let a missing/unparseable `go` abort under pipefail.
        have=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//' | cut -d. -f1,2 || true)
        if [[ -n "$have" && "$have" != "$want" ]]; then
            tom-echo-yellow "'go' ${have}.x is installed but go.mod pins ${want}.x. Run ./scripts/go/setup.sh to align versions."
        fi
        return 0
    fi

    # `snap info`, not `snap list` (whose Tracking column truncates when piped);
    # `|| true` so a non-snap binary (e.g. the lxd shim) doesn't abort pipefail.
    tracking=$(snap info "$tool" 2>/dev/null | awk '/^tracking:/ {print $2; exit}' || true)
    [[ -z "$tracking" ]] && return 0
    if [[ "$tracking" != "$expected" ]]; then
        tom-echo-yellow "'${tool}' is tracking snap channel '${tracking}' but the pinned channel is '${expected}'. Reinstall with the matching setup script to align versions."
    fi
}

# Ensure a command exists, auto-installing on Ubuntu (CI runners and build VMs)
# and warning on version drift. charmcraft/rockcraft/lxd route through concierge,
# which runs only when one is missing or on the wrong channel.
# Usage: requires <command> [message]   (require is an alias)
requires() {
    local cmd="${1:?Usage: requires <command> [message]}"
    # shellcheck disable=SC2016  # the single quotes are inside a double-quoted default; ${cmd} expands
    local msg="${2:-${cmd} is required but not installed. Please install '${cmd}' to proceed.}"

    if _concierge_managed "$cmd"; then
        # Fast path: already installed at the pinned channel -> nothing to do.
        if command -v "$cmd" &>/dev/null && _pinned_channel_ok "$cmd"; then
            return 0
        fi
        # Missing or version mismatch -> (re)provision via concierge.
        if grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
            _prepare_with_concierge
            hash -r 2>/dev/null || true
            command -v "$cmd" &>/dev/null && return 0
            die "'${cmd}' is still not available after running concierge (ensure /snap/bin is in PATH)."
        elif [[ -n "${GITHUB_ACTIONS:-}" ]]; then
            die "'${cmd}' is required but not installed and the CI runner is not Ubuntu -- cannot auto-install."
        fi
        die "${msg}"
    fi

    if command -v "$cmd" &>/dev/null; then
        _check_pinned_version "$cmd"
        return 0
    fi

    # Auto-install known commands on Ubuntu hosts. This covers both GitHub
    # Actions runners and local build VMs.
    if grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
        local install_fn
        install_fn="$(_install_map_lookup "$cmd")"
        if [[ -n "$install_fn" ]]; then
            tom-echo "'${cmd}' not found -- installing..."
            $install_fn
            # Refresh bash's command-lookup cache so a just-installed snap
            # (in /snap/bin) is visible in this same shell.
            hash -r 2>/dev/null || true
            if command -v "$cmd" &>/dev/null; then
                return 0
            fi
            die "installed '${cmd}' but it is not on PATH -- ensure /snap/bin is in PATH."
        fi
    elif [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        die "'${cmd}' is required but not installed and the CI runner is not Ubuntu -- cannot auto-install."
    fi

    die "${msg}"
}

# Copy a craft tool's craft-cli logs into <dest> so build failures can be
# reviewed (and uploaded as CI artifacts) after the fact. Best-effort: never
# fails the caller, so it is safe to wire up as an EXIT trap.
# Usage: collect_craft_logs <rockcraft|charmcraft> <dest-dir>
collect_craft_logs() {
    local tool="${1:?Usage: collect_craft_logs <tool> <dest-dir>}"
    local dest="${2:?Usage: collect_craft_logs <tool> <dest-dir>}"
    local src="${HOME}/.local/state/${tool}/log"
    [[ -d "$src" ]] || return 0
    dest="${dest%/}/${tool}"
    mkdir -p "$dest"
    cp -a "$src/." "$dest/" 2>/dev/null || true
    tom-echo "Collected ${tool} logs into ${dest}"
}
