#!/usr/bin/env bash
# Build the Mono runtime from source, compile test-program.cs, and run it.
#
# Usage:
#   ./scripts/build-and-test.sh
#
# Environment variables (optional):
#   JOBS   – number of parallel make jobs (default: nproc)
#   CFLAGS / CXXFLAGS – compiler flags forwarded to configure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
CFLAGS="${CFLAGS:--ggdb3 -O2}"
CXXFLAGS="${CXXFLAGS:--ggdb3 -O2}"

echo "=== Step 1: autogen.sh ==="
./autogen.sh \
    CFLAGS="${CFLAGS}" \
    CXXFLAGS="${CXXFLAGS}" \
    --with-crash-privacy=no

echo ""
echo "=== Step 2: Fetch monolite bootstrap (C# compiler fallback) ==="
make get-monolite-latest

echo ""
echo "=== Step 3: Build (${JOBS} jobs) ==="
make -j"${JOBS}" -w V=1

echo ""
echo "=== Step 4: Verify built runtime ==="
mono/mini/mono-sgen --version

echo ""
echo "=== Step 5: Compile test-program.cs ==="
# Use the freshly built mono-sgen to drive mcs.
# mcs/class/lib/build/mcs.exe is the bootstrap compiler produced by the build.
mono/mini/mono-sgen mcs/class/lib/build/mcs.exe test-program.cs

echo ""
echo "=== Step 6: Run test-program.exe ==="
mono/mini/mono-sgen test-program.exe

echo ""
echo "=== Build-and-test completed successfully ==="
