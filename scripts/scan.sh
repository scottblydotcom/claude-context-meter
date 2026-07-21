#!/usr/bin/env bash
# Full local security scan: Gitleaks + Semgrep + Trivy
# Run manually before releases or pull requests.
# Usage: ./scripts/scan.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

# GUI git clients and IDE-integrated terminals often launch with a minimal PATH
# that skips Homebrew, since Homebrew's PATH setup normally comes from shell rc
# files sourced only by interactive login shells. Prepend both known Homebrew
# prefixes (if present) so require_tool below can still find the tools there.
for dir in /opt/homebrew/bin /usr/local/bin; do
    if [ -d "$dir" ] && [[ ":$PATH:" != *":$dir:"* ]]; then
        PATH="$dir:$PATH"
    fi
done

# Resolves a tool via PATH instead of a hardcoded Homebrew prefix, since Intel
# Homebrew installs to /usr/local/bin and Apple Silicon Homebrew installs to
# /opt/homebrew/bin. Fails loudly (not as a scan failure) if the tool is missing.
#
# `exit` here would only terminate the command-substitution subshell when this
# function is called as `VAR="$(require_tool ...)"`, not the script itself — so
# this prints to stderr and returns non-zero instead; callers must check the
# command substitution's exit status directly.
require_tool() {
    local tool="$1"
    local resolved
    if ! resolved="$(command -v "$tool")"; then
        echo -e "${RED}[ERROR]${NC} '$tool' not found on PATH — install it (e.g. \`brew install $tool\`) before running this script." >&2
        return 1
    fi
    echo "$resolved"
}

echo ""
echo "========================================"
echo "  Claude Context Meter — Security Scan"
echo "========================================"
echo ""

# ── Gitleaks ─────────────────────────────────────────────────────────────────
info "Running Gitleaks (secret scanning)..."
GITLEAKS_BIN="$(require_tool gitleaks)" || exit 2
if "$GITLEAKS_BIN" detect \
    --source "$REPO_ROOT" \
    --no-banner \
    --redact \
    --exit-code 1 \
    2>&1; then
    pass "Gitleaks: no secrets found"
else
    fail "Gitleaks: secrets detected — review output above"
fi

echo ""

# ── Semgrep ───────────────────────────────────────────────────────────────────
info "Running Semgrep (static analysis)..."
SEMGREP_BIN="$(require_tool semgrep)" || exit 2
if "$SEMGREP_BIN" scan \
    --config=auto \
    --quiet \
    --error \
    "$REPO_ROOT" \
    2>&1; then
    pass "Semgrep: no issues found"
else
    fail "Semgrep: issues detected — review output above"
fi

echo ""

# ── Trivy ─────────────────────────────────────────────────────────────────────
info "Running Trivy (vulnerability scan)..."
TRIVY_BIN="$(require_tool trivy)" || exit 2
# Use a minimal Docker config to avoid Docker Desktop credential errors
TRIVY_DOCKER_CFG="$(mktemp -d)"
echo '{}' > "$TRIVY_DOCKER_CFG/config.json"
if DOCKER_CONFIG="$TRIVY_DOCKER_CFG" "$TRIVY_BIN" fs \
    --exit-code 1 \
    --severity HIGH,CRITICAL \
    --quiet \
    "$REPO_ROOT" \
    2>&1; then
    pass "Trivy: no HIGH/CRITICAL vulnerabilities found"
else
    fail "Trivy: vulnerabilities detected — review output above"
fi
rm -rf "$TRIVY_DOCKER_CFG"

echo ""
echo "========================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"
echo ""

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
