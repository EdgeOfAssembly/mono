# Linux + Mono — Complete Developer Guide

Linux is a **first-class** supported platform for this repository.
A dedicated CI job (`.github/workflows/linux-mono.yml`) runs on every
push to `main` and on every pull request, enforcing that Mono compiles
and that the core test suites pass.

---

## Table of Contents

1. [How the build is guaranteed](#how-the-build-is-guaranteed)
2. [Supported versions](#supported-versions)
3. [System prerequisites](#system-prerequisites)
4. [Getting the source](#getting-the-source)
5. [Building Mono from source](#building-mono-from-source)
6. [Verifying the build](#verifying-the-build)
7. [Installing Mono system-wide](#installing-mono-system-wide)
8. [Writing, compiling, and running a C# application](#writing-compiling-and-running-a-c-application)
9. [Running an existing Windows .exe on Linux](#running-an-existing-windows-exe-on-linux)
10. [Useful runtime flags and environment variables](#useful-runtime-flags-and-environment-variables)
11. [Running GUI apps (Windows Forms / GTK#)](#running-gui-apps-windows-forms--gtk)
12. [Running tests](#running-tests)
13. [Faster iteration with ccache](#faster-iteration-with-ccache)
14. [CI workflow details](#ci-workflow-details)
15. [Troubleshooting](#troubleshooting)
16. [Known exclusions and follow-ups](#known-exclusions-and-follow-ups)

---

## How the build is guaranteed

The GitHub Actions workflow runs every build and test job inside the
**exact same pre-built Docker container** that the upstream Azure
Pipelines CI uses:

`mcr.microsoft.com/dotnet-buildtools/prereqs:ubuntu-18.04-mono-amd64`

This container contains:

- Ubuntu 18.04 base (stable, long-term support)
- GCC / G++ / Make / Autoconf / Automake / CMake / Python 3
- Mono 6.x bootstrap compiler
- All required native libraries (GLib, zlib, gettext, …)

Because the environment is fully pinned and pre-tested by the .NET
infrastructure team, there are **no runtime apt downloads** and **no
version mismatches**—the leading causes of intermittent build
failures.

Additionally, a `monolite` fallback bootstrap is fetched before every
build. Monolite is a minimal pre-compiled `mcs` binary maintained by
the Mono project. If the container's Mono bootstrap ever becomes
incompatible with HEAD, monolite takes over automatically and the
build still succeeds.

---

## Supported versions

| Role | Version | Notes |
|------|---------|-------|
| **Bootstrap compiler** (build-time only) | Mono 6.x | Provided by the Docker container; used only during `autogen.sh`/`make` to compile C# sources. The resulting binary is independent of this version. |
| **Monolite fallback** | Latest published | Downloaded via `make get-monolite-latest` from `download.mono-project.com` (mutable `-latest` tarball, no checksum verification). Used only if the container/system Mono cannot bootstrap HEAD. See the security note below. |

> **Security note — monolite:** `make get-monolite-latest` fetches a
> pre-built `mcs.exe` over TLS from `download.mono-project.com` without
> an integrity check (no hash or signature verification).  A compromised
> distribution point could inject code into build outputs.  If
> supply-chain integrity is critical, vendor the tarball at a specific
> version, verify its hash offline, and point the `monolite_url` variable
> to your internal mirror instead.
| **Built runtime** | HEAD | This is what the repository produces. |

CI validated on: Ubuntu 18.04 LTS (inside container), runner host Ubuntu 22.04, amd64.

---

## System prerequisites

### Ubuntu / Debian (recommended)

```bash
sudo apt-get update
sudo apt-get install -y \
    mono-complete \
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
    libglib2.0-dev \
    zlib1g-dev
```

### Fedora / RHEL / AlmaLinux

```bash
sudo dnf install -y \
    mono-core \
    autoconf automake libtool \
    gcc gcc-c++ make \
    gettext cmake python3 \
    curl wget bc \
    glib2-devel zlib-devel
```

### Arch Linux

```bash
sudo pacman -S --needed \
    mono \
    autoconf automake libtool \
    base-devel gettext cmake python \
    curl wget bc \
    glib2 zlib
```

### No pre-installed Mono? Use monolite

If you cannot install `mono-complete` (e.g., on a minimal CI container
or a distro where Mono is unavailable), use the **monolite** bootstrap
instead — no prior Mono installation needed:

```bash
./autogen.sh
make get-monolite-latest   # downloads just enough to run mcs
make -j"$(nproc)"
```

---

## Getting the source

```bash
# Full clone with all submodules (required — the build uses several
# external libraries from the submodules)
git clone --recurse-submodules https://github.com/EdgeOfAssembly/mono.git
cd mono

# If you already cloned without submodules, initialise them now:
git submodule update --init --recursive
```

---

## Building Mono from source

### Standard build (with system Mono bootstrap)

```bash
# 1. Generate the build system
./autogen.sh CFLAGS="-ggdb3 -O2" CXXFLAGS="-ggdb3 -O2"

# 2. Compile (use all available CPU cores)
make -j"$(nproc)"
```

### Guaranteed build (monolite fallback — identical to what CI does)

```bash
./autogen.sh CFLAGS="-ggdb3 -O2" CXXFLAGS="-ggdb3 -O2"
make get-monolite-latest   # always downloads the monolite tarball; the pre-built mcs it provides is used as fallback if system Mono cannot bootstrap HEAD
make -j"$(nproc)"
```

`make get-monolite-latest` always downloads the monolite tarball, but the
pre-built fallback compiler it provides is only used if the normal bootstrap
with the container/system Mono fails during the subsequent `make`.

### Build only the native runtime (skip class libraries)

Useful when iterating on the JIT or GC:

```bash
./autogen.sh --disable-mcs-build CFLAGS="-ggdb3 -O2"
make -j"$(nproc)" -C mono/mini
```

### Build with LLVM backend (optional)

```bash
./autogen.sh --enable-llvm CFLAGS="-ggdb3 -O2"
make -j"$(nproc)"
```

---

## Verifying the build

```bash
# Print the version of the freshly built runtime
./mono/mini/mono-sgen --version
# Expected output: Mono JIT compiler version X.Y.Z (...)

# Quick sanity check — compile and run a one-liner
echo 'class Hi { static void Main() { System.Console.WriteLine("Mono works!"); } }' > /tmp/hi.cs
./mono/mini/mono-sgen mcs/mcs.exe /tmp/hi.cs -out:/tmp/hi.exe
./mono/mini/mono-sgen /tmp/hi.exe
# Output: Mono works!
```

---

## Installing Mono system-wide

After a successful build you can install Mono into `/usr/local` (default
prefix) so that `mono` and `mcs` are on your `PATH`:

```bash
sudo make install

# Verify
mono --version
mcs --version
```

To install to a custom prefix (e.g. `~/mono-local`):

```bash
./autogen.sh --prefix="$HOME/mono-local" CFLAGS="-ggdb3 -O2"
make -j"$(nproc)"
make install
export PATH="$HOME/mono-local/bin:$PATH"
mono --version
```

---

## Writing, compiling, and running a C# application

### Hello, World

```csharp
// File: hello.cs
using System;

class Hello
{
    static void Main(string[] args)
    {
        Console.WriteLine("Hello from Mono on Linux!");
        if (args.Length > 0)
            Console.WriteLine("Arguments: " + string.Join(", ", args));
    }
}
```

**Compile:**

```bash
mcs hello.cs -out:hello.exe
```

**Run:**

```bash
mono hello.exe
# Hello from Mono on Linux!

mono hello.exe foo bar
# Hello from Mono on Linux!
# Arguments: foo, bar
```

### Multi-file project

```bash
mcs *.cs -out:myapp.exe
mono myapp.exe
```

### Reference an external DLL

```bash
mcs main.cs -r:SomeLibrary.dll -out:myapp.exe
mono myapp.exe
```

### Using NuGet packages

`nuget` is not installed by this repository's `make install`.
Install it separately via your distro's package manager (it is included
in `mono-complete` on Ubuntu/Debian), and then use it to restore packages:

```bash
# Ubuntu / Debian — nuget ships as part of mono-complete
sudo apt-get install -y nuget

# Restore packages for your project
nuget install Newtonsoft.Json

# nuget creates a packages/ subdirectory; replace X.Y.Z with the actual version
DLL=$(ls packages/Newtonsoft.Json.*/lib/net45/Newtonsoft.Json.dll | head -1)
mcs main.cs -r:"$DLL" -out:myapp.exe
mono myapp.exe
```

### Debug build and step through with the Mono debugger

```bash
# Compile with debug symbols
mcs -debug hello.cs -out:hello.exe

# Run under the soft debugger (listens on port 10000)
mono --debug --debugger-agent=transport=dt_socket,server=y,address=127.0.0.1:10000 hello.exe &

# Attach with mdbg or any IDE that supports the Mono debugger protocol
```

---

## Running an existing Windows .exe on Linux

Any .NET Framework assembly compiled on Windows can be run on Linux
with Mono — no recompilation needed.

```bash
# Copy the .exe (and any required .dll files) to Linux, then:
mono MyWindowsApp.exe

# Pass arguments exactly as you would on Windows:
mono MyWindowsApp.exe --config prod.xml --verbose
```

### What works out of the box

- Console apps, class libraries, WCF services, ASP.NET (via xsp4)
- Most of `System.*`, `Microsoft.Build.*`, `System.Net.Http`
- Entity Framework 6, NUnit, xUnit, many NuGet packages

### What may need adaptation

| Feature | Notes |
|---------|-------|
| Windows paths (`C:\…`) | Use `Path.Combine`/`Path.DirectorySeparatorChar` in code; pass Linux paths on the command line |
| Registry access (`Microsoft.Win32.Registry`) | Mono emulates the registry in `~/.config/mono/registry`; keys used only for configuration usually work |
| Windows-only P/Invoke (`kernel32.dll`, etc.) | Will throw `DllNotFoundException`; replace with POSIX equivalents |
| COM / ActiveX | Not supported |
| WPF | Not supported; use GTK# or Avalonia for cross-platform GUI |

### TLS / HTTPS

By default Mono uses its own certificate store.  To import the
system's trusted CA certificates:

```bash
# One-time setup — import Mozilla's root CA bundle
cert-sync /etc/ssl/certs/ca-certificates.crt
```

---

## Useful runtime flags and environment variables

### Command-line flags

| Flag | Description |
|------|-------------|
| `mono --version` | Print runtime version and exit |
| `mono --debug` | Enable debug mode (better stack traces) |
| `mono --trace=MyNamespace` | Trace method calls in a namespace |
| `mono --profile` | Run with the default profiler |
| `mono --profile=log:output=prof.mlpd` | Log profiler output to a file |
| `mono --aot` | Ahead-of-time compile an assembly |
| `mono --llvm` | Use the LLVM backend (if built with `--enable-llvm`) |

### Environment variables

| Variable | Example | Description |
|----------|---------|-------------|
| `MONO_LOG_LEVEL` | `debug` | Verbosity: `error` `critical` `warning` `message` `info` `debug` |
| `MONO_LOG_MASK` | `all` | Subsystems to log: `asm` `type` `dll` `gc` `cfg` `aot` `all` |
| `MONO_PATH` | `/opt/mylibs` | Additional directories searched for assemblies |
| `MONO_GAC_PREFIX` | `/usr/local` | Prefix(es) searched for the GAC |
| `MONO_ENV_OPTIONS` | `--debug` | Options prepended to every `mono` invocation |
| `MONO_TLS_PROVIDER` | `legacy` or `btls` | TLS implementation to use |
| `MONO_DISABLE_SHM` | `1` | Disable shared memory (useful in containers) |
| `MONO_GC_PARAMS` | `max-heap-size=512m` | Tune the SGen GC |
| `MONO_GC_DEBUG` | `check-remset` | GC debug flags |

### Diagnosing assembly load failures

```bash
MONO_LOG_LEVEL=debug MONO_LOG_MASK=asm mono MyApp.exe 2>&1 | grep -i "loaded\|not found"
```

### Diagnosing DllNotFoundException

```bash
MONO_LOG_LEVEL=debug MONO_LOG_MASK=dll mono MyApp.exe 2>&1 | grep -i "dll\|native"
```

---

## Running GUI apps (Windows Forms / GTK#)

### Windows Forms

Windows Forms is supported on Linux via a Mono-internal implementation
built on top of X11 (libgdiplus).

```bash
# Install libgdiplus (provides GDI+ compatible rendering)
sudo apt-get install -y libgdiplus

# Compile a WinForms app
mcs -r:System.Windows.Forms.dll -r:System.Drawing.dll myform.cs -out:myform.exe

# Run (requires an X11 display)
mono myform.exe

# Headless (virtual framebuffer)
sudo apt-get install -y xvfb
xvfb-run mono myform.exe
```

### GTK#

GTK# provides native-looking widgets on Linux and is the recommended
GUI framework for new cross-platform Mono apps.

```bash
# Install GTK# bindings
sudo apt-get install -y gtk-sharp2   # or gtk-sharp3 on newer distros

# Compile
mcs -pkg:gtk-sharp-2.0 mygtkapp.cs -out:mygtkapp.exe

# Run
mono mygtkapp.exe
```

---

## Running tests

All commands assume the repository root as the working directory.

### Core smoke tests (fast, ~15 min total)

```bash
make -w -C mono/mini    -k check           # JIT mini tests
make -w -C mono/unit-tests -k check        # Runtime unit tests
make -w -C mono/eglib/test -k check        # eglib unit tests
```

### Compiler tests (~60 min)

```bash
make -w -C mcs/tests  run-test
make -w -C mcs/errors run-test
```

### Class-library tests (selective)

```bash
make -w -C mcs/class/corlib            run-test
MONO_TLS_PROVIDER=legacy \
  make -w -C mcs/class/System          run-test
make -w -C mcs/class/System.XML        run-test
make -w -C mcs/class/System.Security   run-test
```

### Full test suite (several hours)

```bash
make check
```

Or mirror exactly what CI runs:

```bash
CI_TAGS="linux-amd64" scripts/ci/run-jenkins.sh
```

---

## Faster iteration with ccache

`ccache` caches compiled C/C++ object files and reduces full rebuilds
from ~2 h to ~5 min after the first pass.

```bash
sudo apt-get install -y ccache
ccache --max-size=4G

export CC="ccache gcc"
export CXX="ccache g++"

./autogen.sh CFLAGS="-ggdb3 -O2" CXXFLAGS="-ggdb3 -O2"
make -j"$(nproc)"

# Hit/miss statistics
ccache --show-stats
```

The CI workflow caches `~/.ccache` between runs via `actions/cache`,
keyed by commit SHA with a branch-level fallback restore key.

---

## CI workflow details

File: `.github/workflows/linux-mono.yml`

| Aspect | Value |
|--------|-------|
| Trigger | Push to `main`/release branches; every PR |
| Runner | `ubuntu-22.04` (GitHub-hosted) |
| Container | `mcr.microsoft.com/dotnet-buildtools/prereqs:ubuntu-18.04-mono-amd64` |
| Concurrency | One run per branch; in-progress run cancelled on new push |
| Build flags | `CFLAGS="-ggdb3 -O2"`, `--with-crash-privacy=no` |
| Bootstrap | Container Mono **+** monolite fallback |
| Speed | `ccache` with persistent `actions/cache` |
| Tests | mini JIT · mini AOT · runtime unit · eglib · compiler · compiler errors · corlib |
| Artifacts | NUnit XML results uploaded per run |
| GITHUB_TOKEN | `contents: read` (minimal scope) |
| Timeout | 180 min |

A failure in this workflow **blocks merging**, making Linux+Mono a
first-class constraint rather than a best-effort target.

---

## Troubleshooting

### `mcs: command not found` / `csc: command not found` during `autogen.sh`

Install the bootstrap Mono:

```bash
sudo apt-get install -y mono-complete
mono --version   # must print a version
```

Or use the monolite fallback (no system Mono required):

```bash
./autogen.sh
make get-monolite-latest
make -j"$(nproc)"
```

### `configure: error: C compiler cannot create executables`

```bash
sudo apt-get install -y build-essential
gcc --version
```

### `/usr/bin/ld: cannot find -lglib-2.0`

```bash
sudo apt-get install -y libglib2.0-dev
```

### `error: possibly undefined macro: AC_PROG_LIBTOOL`

```bash
sudo apt-get install -y libtool
```

### Submodule errors (`fatal: not a git repository`)

```bash
git submodule update --init --recursive
```

### `make: *** No targets.  Stop.` after a failed `autogen.sh`

Clean everything and reconfigure:

```bash
git clean -xdf    # WARNING: removes all untracked files
./autogen.sh CFLAGS="-ggdb3 -O2"
```

### `DllNotFoundException` when running an app

The native library is either missing or has a different name on Linux.

```bash
# Find out which library Mono is trying to load
MONO_LOG_LEVEL=debug MONO_LOG_MASK=dll mono MyApp.exe 2>&1 | grep -i dll

# Install the missing library (example for libz)
sudo apt-get install -y zlib1g-dev
```

### HTTPS / TLS errors (`The authentication or decryption has failed`)

```bash
# Sync the system CA certificates into Mono's trust store
cert-sync /etc/ssl/certs/ca-certificates.crt

# Or force the legacy TLS provider
MONO_TLS_PROVIDER=legacy mono MyApp.exe
```

### Windows Forms app shows no window / crashes

```bash
sudo apt-get install -y libgdiplus

# If running headless (no display):
sudo apt-get install -y xvfb
xvfb-run mono MyApp.exe
```

### Build is slow / ccache not helping

Make sure the compiler wrappers are active **before** `./autogen.sh`:

```bash
export CC="ccache gcc" CXX="ccache g++"
./autogen.sh CFLAGS="-ggdb3 -O2" CXXFLAGS="-ggdb3 -O2"
make -j"$(nproc)"
```

If `CC` is set after `autogen.sh`, the generated Makefiles already have
`gcc` hard-coded; re-run `autogen.sh`.

---

## Known exclusions and follow-ups

| Area | CI status | Notes |
|------|-----------|-------|
| `System.Windows.Forms` GUI tests | Excluded | Require an X11 display. Run locally: `xvfb-run make -C mcs/class/System.Windows.Forms run-test`. Follow-up: add `xvfb-run` step to CI. |
| `btls` (BoringSSL) TLS tests | Excluded | Long build time. Enable locally with `--enable-btls`. |
| AOT check | `continue-on-error: true` | Requires optional native AOT tooling; failures logged but don't block the job. |
| ARM / ARM64 | Separate Azure Pipelines lanes | `armhf` and `aarch64` are validated by Azure Pipelines; GitHub Actions covers `amd64` only. |

