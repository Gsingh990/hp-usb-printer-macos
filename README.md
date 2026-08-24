# hpcups-macos

Make a USB-attached HP inkjet work on modern macOS, using HP's own driver.

macOS has deprecated classic printer drivers in favour of AirPrint/IPP. That is
fine for network printers, but a **USB-only** HP inkjet has no AirPrint path at
all — and the generic driver macOS falls back to does not speak the printer's
language. The result is a printer that appears installed, accepts jobs, and
prints nothing.

This repo builds HP's real raster driver, `hpcups`, for macOS and installs it as
a normal CUPS queue.

## The problem, concretely

macOS attaches USB printers it does not recognise to a **"Generic PCL Laser
Printer"** PPD, which drives the `rastertohp` filter and emits **PCL5 laser**.
Consumer HP inkjets do not implement PCL5. They advertise their real language in
their USB device ID:

```
CMD:PCL3GUI,PJL,Automatic,JPEG,DW-PCL,DESKJET,DYN
```

`PCL3GUI` is a different raster language. Sending PCL5 to it produces a job that
either hangs forever or ejects blank paper. The generic PPD is also hardcoded to
monochrome (`cupsColorSpace 3`), so even in principle it could never print
colour on a four-ink printer.

**Why not driverless?** IPP-over-USB requires a USB interface with class 7,
subclass 1, **protocol 4**. USB-only consumer models typically expose only
protocol 2 (raw bulk):

```
$ ioreg -w0 -l -p IOService -n "<your printer>" -r -d 3 | grep bInterface
    "bInterfaceClass" = 7
    "bInterfaceSubClass" = 1
    "bInterfaceProtocol" = 2      <-- no protocol 4, so no ipp-usb
```

If yours reports protocol 4, you do not need this repo — use `ipp-usb` and add
the printer driverless.

## Install

```bash
brew install jpeg-turbo
git clone <this repo> && cd hpcups-macos
./build.sh                 # downloads HPLIP source, builds hpcups + PPDs
./install.sh --list        # check your printer and matched PPD
sudo ./install.sh
```

`build.sh` produces `hpcups` plus **848 PPDs** covering HP's supported range
(DeskJet, OfficeJet, Envy, Smart Tank, Photosmart, LaserJet). `install.sh`
auto-detects a USB HP printer, matches it to a PPD, and creates the queue.

To pick explicitly:

```bash
sudo ./install.sh --device 'usb://HP/...' --ppd build/ppd/hp-<model>.ppd --name MyPrinter
```

Remove:

```bash
sudo ./uninstall.sh <queue-name> [--purge]
```

## What was actually verified

Verified end to end on:

- **HP Smart Tank 520/540 series**, USB, printing text and colour documents
- **macOS 27 (Tahoe)**, Apple Silicon, CUPS 2.3.4
- HPLIP **3.23.12**

Everything else is **untested by me**. The build produces PPDs for hundreds of
models because HPLIP supports them, not because I have tried them. If your model
is in `build/ppd/` there is a good chance it works, but that is an expectation,
not a claim.

## Notes on the build

Three parts of HPLIP are Linux-only and are handled explicitly:

| Component | Handling | Consequence |
|---|---|---|
| `hpmud` (HP's USB layer) | stub header; CUPS' own `usb` backend does the I/O | none |
| D-Bus status channel | compiled out (`HAVE_DBUS` undefined) | no ink/status reporting |
| `libImageProcessor` | no-op stub — HP ships it as a Linux-only binary | raster passes through unmodified |

Two macOS-specific details worth knowing if you adapt this:

- **The filter cannot live in `/usr/libexec/cups/filter`.** SIP makes it
  read-only. It goes in `/Library/Printers/`, and the PPD refers to it by
  absolute path in `cupsFilter`, which CUPS accepts.
- **CUPS sandboxes filters**, so a filter linked against a Homebrew dylib fails
  at run time with the library "not found". `build.sh` copies `libjpeg` next to
  the binary and rewrites the load path to `@loader_path`.

## Limitations

- No ink level or printer status reporting (the D-Bus channel is stubbed).
- Scanning is not covered — this is the print path only.
- Built and tested on Apple Silicon only.

## Licensing

No HP code or binaries are redistributed here; HPLIP is downloaded and compiled
on your machine. See [LICENSE-NOTES.md](LICENSE-NOTES.md).
