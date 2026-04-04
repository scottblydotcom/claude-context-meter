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

echo ""
echo "========================================"
echo "  Claude Context Meter — Security Scan"
echo "========================================"
echo ""

# ── Gitleaks ─────────────────────────────────────────────────────────────────
info "Running Gitleaks (secret scanning)..."
if /usr/local/bin/gitleaks detect \
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
if /usr/local/bin/semgrep scan \
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
# Use a minimal Docker config to avoid Docker Desktop credential errors
TRIVY_DOCKER_CFG="$(mktemp -d)"
echo '{}' > "$TRIVY_DOCKER_CFG/config.json"
if DOCKER_CONFIG="$TRIVY_DOCKER_CFG" /usr/local/bin/trivy fs \
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
