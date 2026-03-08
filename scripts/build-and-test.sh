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
CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}" ./autogen.sh \
    --with-crash-privacy=no

echo ""
echo "=== Step 2: Fetch monolite bootstrap (C# compiler fallback) ==="
make get-monolite-latest

echo ""
echo "=== Step 3: Build (${JOBS} jobs) ==="
make -j"${JOBS}" -w V=1

echo ""
echo "=== Step 4: Verify built runtime ==="
# Use the in-tree mono wrapper and freshly built class libraries for all runtime invocations.
MONO_WRAPPER="${REPO_ROOT}/runtime/mono-wrapper"
export MONO_PATH="${REPO_ROOT}/mcs/class/lib/build"

"${MONO_WRAPPER}" --version

echo ""
echo "=== Step 5: Compile test-program.cs ==="
# Use the freshly built runtime (via mono-wrapper) to drive mcs.
# mcs/class/lib/build/mcs.exe is the bootstrap compiler produced by the build.
"${MONO_WRAPPER}" mcs/class/lib/build/mcs.exe test-program.cs

echo ""
echo "=== Step 6: Run test-program.exe ==="
"${MONO_WRAPPER}" test-program.exe

echo ""
echo "=== Build-and-test completed successfully ==="
