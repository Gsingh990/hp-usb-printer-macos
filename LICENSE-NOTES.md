# Licensing

This repository contains **no HP source code and no compiled HP binaries**.

It contains:

- `build.sh`, `install.sh`, `uninstall.sh` — build and packaging scripts
- `shim/hpmud.h` — an empty stub header
- `shim/imageprocessor_stub.cpp` — a no-op stub

`build.sh` downloads the HPLIP source tarball from SourceForge at build time and
compiles it on your machine. HPLIP is distributed by HP under a mix of licences
(BSD-style for much of `prnt/hpcups`, GPLv2+ elsewhere); see the `COPYING` file
in the downloaded tarball.

Building HPLIP locally for your own use is unproblematic. **Redistributing the
resulting `hpcups` binary is a different matter** and would carry source
distribution obligations. That is a deliberate reason this repository ships
scripts rather than binaries.
