# Linux + Mono Developer Guide

Linux is a first-class supported platform for this repository.
A dedicated CI job (`.github/workflows/linux-mono.yml`) runs on every
push to `main` and on every pull request, enforcing that the full build
compiles and that the core test suites pass.

---

## Table of Contents

1. [Supported Mono versions](#supported-mono-versions)
2. [System prerequisites](#system-prerequisites)
3. [Getting the source](#getting-the-source)
4. [Building](#building)
5. [Running tests](#running-tests)
6. [Faster iteration with ccache](#faster-iteration-with-ccache)
7. [CI workflow](#ci-workflow)
8. [Troubleshooting](#troubleshooting)
9. [Known exclusions and follow-ups](#known-exclusions-and-follow-ups)

---

## Supported Mono versions

| Role | Minimum version | Notes |
|------|----------------|-------|
| **Bootstrap compiler** (required at build time) | 6.x | Installed from OS packages; used only during `autogen.sh`/`make` to compile the C# sources. The resulting binary is independent of the bootstrap version. |
| **Built runtime** | HEAD | This is what the repository produces. |

Validated against Ubuntu 22.04 LTS (amd64) in CI.

---

## System prerequisites

### Ubuntu / Debian

```bash
sudo apt-get update
sudo apt-get install -y \
    # Bootstrap C# compiler
    mono-complete \
    # Build toolchain
    autoconf \
    automake \
    libtool \
    build-essential \
    gettext \
    cmake \
    python3 \
    curl \
    wget \
    bc \
    # Runtime libraries
    libglib2.0-dev \
    zlib1g-dev
```

### Fedora / RHEL / AlmaLinux

```bash
sudo dnf install -y \
    mono-core \
    autoconf \
    automake \
    libtool \
    gcc \
    gcc-c++ \
    make \
    gettext \
    cmake \
    python3 \
    curl \
    wget \
    bc \
    glib2-devel \
    zlib-devel
```

### Arch Linux

```bash
sudo pacman -S --needed \
    mono \
    autoconf \
    automake \
    libtool \
    base-devel \
    gettext \
    cmake \
    python \
    curl \
    wget \
    bc \
    glib2 \
    zlib
```

---

## Getting the source

```bash
# Full clone with all submodules (recommended)
git clone --recurse-submodules https://github.com/EdgeOfAssembly/mono.git
cd mono

# If you already cloned without submodules
git submodule update --init --recursive
```

---

## Building

### Standard build

```bash
# 1. Configure
./autogen.sh CFLAGS="-ggdb3 -O2" CXXFLAGS="-ggdb3 -O2"

# 2. Build (parallel – use all available cores)
make -j"$(nproc)"
```

The resulting runtime binary is `mono/mini/mono-sgen`.

```bash
./mono/mini/mono-sgen --version
# Mono JIT compiler version X.Y.Z (HEAD ...)
```

### Bootstrap from monolite (no pre-installed Mono required)

If you cannot install `mono-complete` system-wide, you can bootstrap
from the minimal *monolite* distribution:

```bash
./autogen.sh
make get-monolite-latest   # downloads just enough to run mcs
make -j"$(nproc)"
```

### Build with LLVM (optional, requires LLVM 12+)

```bash
./autogen.sh --enable-llvm CFLAGS="-ggdb3 -O2"
make -j"$(nproc)"
```

### Install

```bash
sudo make install
# Verify:
mono --version
```

---

## Running tests

All test commands below assume you are in the repository root.

### Core smoke tests (fast, ~15 min total)

```bash
# JIT mini tests
make -w -C mono/mini -k check

# Runtime unit tests
make -w -C mono/unit-tests -k check

# eglib unit tests
make -w -C mono/eglib/test -k check
```

### Compiler tests (~60 min)

```bash
make -w -C mcs/tests run-test
make -w -C mcs/errors run-test
```

### Class library tests (selective)

```bash
# corlib
make -w -C mcs/class/corlib run-test

# System
MONO_TLS_PROVIDER=legacy make -w -C mcs/class/System run-test

# System.XML
make -w -C mcs/class/System.XML run-test
```

### Full test suite (several hours)

```bash
make check
```

Or use the CI script directly (mirrors what GitHub Actions runs):

```bash
CI_TAGS="linux-amd64" scripts/ci/run-jenkins.sh
```

---

## Faster iteration with ccache

`ccache` caches compiled object files and can cut rebuild time from
hours to minutes after the first full build.

```bash
sudo apt-get install -y ccache

# Configure ccache cache size
ccache --max-size=4G

# Expose ccache wrappers as the compiler
export CC="ccache gcc"
export CXX="ccache g++"

./autogen.sh CFLAGS="-ggdb3 -O2" CXXFLAGS="-ggdb3 -O2"
make -j"$(nproc)"

# View hit/miss statistics
ccache --show-stats
```

The GitHub Actions workflow automatically caches the ccache directory
between runs (key: `ccache-linux-amd64-<sha>`).

---

## CI workflow

The file `.github/workflows/linux-mono.yml` defines the Linux+Mono
enforcement job. It:

1. Runs on **push** to `main`/release branches and on every **pull request**.
2. Uses **Ubuntu 22.04** on GitHub-hosted runners.
3. Installs bootstrap Mono from the Ubuntu package archive.
4. Installs all build dependencies.
5. Configures with `./autogen.sh`.
6. Builds with `make -j$(nproc)`.
7. Runs: mini tests · runtime unit tests · eglib tests ·
   compiler tests · corlib tests.
8. Uploads NUnit XML test results as a build artifact.
9. Uses `ccache` with a persistent GitHub Actions cache to
   accelerate subsequent runs.

Failures in this workflow **block merging**, making Linux+Mono a
first-class constraint rather than a best-effort target.

---

## Troubleshooting

### `mcs: command not found` / `csc: command not found`

A working Mono installation is required before running `autogen.sh`.

```bash
sudo apt-get install -y mono-complete
mono --version   # must print a version
```

### `configure: error: C compiler cannot create executables`

```bash
sudo apt-get install -y build-essential
gcc --version    # confirm gcc is available
```

### `/usr/bin/ld: cannot find -lglib-2.0`

```bash
sudo apt-get install -y libglib2.0-dev
```

### `make: *** No targets.  Stop.` after a failed `autogen.sh`

Delete any partial state and reconfigure from scratch:

```bash
git clean -xdf    # WARNING: removes all untracked files
./autogen.sh CFLAGS="-ggdb3 -O2"
```

### Test failures — missing X server (`System.Windows.Forms`)

Windows Forms tests require a display. Run them under a virtual
framebuffer or skip if irrelevant:

```bash
sudo apt-get install -y xvfb
xvfb-run make -w -C mcs/class/System.Windows.Forms run-test
```

### Slow builds

* Install and enable `ccache` (see [above](#faster-iteration-with-ccache)).
* Use all available cores: `make -j"$(nproc)"`.
* Build only the runtime (skip class libraries): add
  `--disable-mcs-build` to `autogen.sh` and run
  `make -C mono/mini`.

### Submodule errors (`fatal: not a git repository`)

```bash
git submodule update --init --recursive
```

---

## Known exclusions and follow-ups

| Area | Status | Notes |
|------|--------|-------|
| `System.Windows.Forms` GUI tests | Excluded in CI | Require an X11 display; run locally with `xvfb-run`. Follow-up: add `xvfb-run` step to workflow. |
| `btls` (BoringSSL) TLS tests | Excluded in CI | BoringSSL build adds significant time; use `--enable-btls` locally if testing TLS scenarios. |
| ARM / ARM64 | Validated separately | Azure Pipelines jobs handle `armhf` and `aarch64`; GitHub Actions job covers `amd64` only. |
