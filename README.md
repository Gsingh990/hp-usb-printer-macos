# hp-usb-printer-macos

**Fix an HP printer that won't print over USB on macOS — prints blank pages, hangs on
"Sending data to printer", or shows up as a "Generic PCL Laser Printer".**

Builds HP's own raster driver (`hpcups`, from HPLIP) for macOS and installs it as a
normal CUPS print queue. For HP DeskJet, OfficeJet, Envy, Smart Tank, Photosmart and
LaserJet models connected by **USB**, where AirPrint is not available and Apple has
deprecated classic printer drivers.

---

## Does this apply to you?

If any of these match, yes:

- Your HP printer is connected by **USB cable** (not Wi-Fi / network).
- macOS installed it automatically as **"Generic PCL Laser Printer"**.
- Print jobs **eject blank pages**, or print **garbled / slanted / smeared** output.
- Jobs sit forever at **"Sending data to printer"** and never finish.
- The queue disables itself with **"Unable to send data to printer."**
- The printer **pulls a sheet of paper and then stalls**, needing a power cycle.
- **HP Smart** app or **HP Easy Start** won't set it up, or there is **no driver
  download** for your macOS version.
- macOS says the printer **"software is not available"** or offers only AirPrint.
- Printing works fine from **Android (NokoPrint)** or **Windows**, but not from your Mac.

Common searches that land here: *HP printer prints blank pages Mac*, *HP USB printer
not working macOS*, *HP Smart Tank Mac driver*, *HP DeskJet USB Mac no driver*,
*macOS printer driver deprecated*, *Generic PCL Laser Printer Mac*, *hpcups macOS*,
*HPLIP macOS*, *PCL3GUI driver Mac*, *printer stuck sending data to printer Mac*.

---

## Why this happens

macOS attaches USB printers it doesn't recognise to a **"Generic PCL Laser Printer"**
PPD, which drives the `rastertohp` filter and emits **PCL5 laser** commands. Consumer
HP inkjets do not implement PCL5. They advertise their real language in their USB
device ID:

```
CMD:PCL3GUI,PJL,Automatic,JPEG,DW-PCL,DESKJET,DYN
```

`PCL3GUI` is a completely different raster language. Sending PCL5 to it produces a job
that hangs or ejects blank paper. That generic PPD is also hardcoded to monochrome
(`cupsColorSpace 3`), so even in principle it could never print colour on a four-ink
printer.

Apple has moved to AirPrint/IPP and deprecated classic drivers. That's fine for network
printers — but a **USB-only** model has no AirPrint path at all.

### Why not driverless / ipp-usb?

IPP-over-USB needs a USB interface with class 7, subclass 1, **protocol 4**. USB-only
consumer models typically expose only protocol 2 (raw bulk). Check yours:

```bash
ioreg -w0 -l -p IOService -n "YOUR PRINTER NAME" -r -d 3 | grep bInterface
```

```
    "bInterfaceClass" = 7
    "bInterfaceSubClass" = 1
    "bInterfaceProtocol" = 2      <-- only protocol 2, so ipp-usb cannot work
```

**If yours reports protocol 4, stop — you don't need this repo.** Install `ipp-usb` and
add the printer driverless instead.

---

## Install

```bash
brew install jpeg-turbo
git clone https://github.com/Gsingh990/hp-usb-printer-macos.git
cd hp-usb-printer-macos
./build.sh                 # downloads HPLIP source, builds hpcups + PPDs
./install.sh --list        # check your printer and the matched PPD
sudo ./install.sh
sudo lpadmin -d <queue>    # optional: make it the default printer
```

`build.sh` produces `hpcups` plus **848 PPDs**. `install.sh` auto-detects a USB HP
printer, matches it to a PPD, and creates the queue.

Choose explicitly if auto-detection picks wrong, or if you have several printers:

```bash
sudo ./install.sh --device 'usb://HP/...' --ppd build/ppd/hp-<model>.ppd --name MyPrinter
```

Remove:

```bash
sudo ./uninstall.sh <queue-name> [--purge]
```

---

## Printer support

PPDs are generated for HP's supported range, roughly:

| Family | PPDs |
|---|---:|
| LaserJet / Color LaserJet | 283 |
| DeskJet | 204 |
| OfficeJet | 150 |
| Photosmart | 102 |
| Envy | 21 |
| Smart Tank / Ink Tank | 21 |

Includes models such as Smart Tank 520 / 530 / 540 / 580 / 720 / 750, DeskJet 2300 /
2700 / 3700 / 4100 series, Ink Tank 310 / 410, OfficeJet Pro, Envy 4500 / 6000, and
many more — run `ls build/ppd/` after building to see the full list.

### What was actually verified

Verified end to end on:

- **HP Smart Tank 520/540 series** over USB — text and colour documents
- **macOS 27.0** (build 26A5416b), Apple Silicon, CUPS 2.3.4
- **HPLIP 3.23.12**

Everything else is **untested by me**. The build produces PPDs for hundreds of models
because HPLIP supports them, not because I have tried them. If your model appears in
`build/ppd/` there's a good chance it works — but that's an expectation, not a claim.
Reports of success or failure on other models are welcome in Issues.

---

## Troubleshooting

**"Unable to send data to printer" / queue keeps disabling itself**
Usually the printer is off, asleep, or its USB endpoint is briefly unavailable after a
power cycle. Re-enable with `cupsenable <queue>` and resend.

**Job completes but the page is blank**
Confirm the queue is using this driver, not the generic one:
```bash
grep cupsFilter /etc/cups/ppd/<queue>.ppd
```
It should point at `/Library/Printers/HP/hpcups/hpcups`.

**Every page comes out completely black (sometimes with coloured stripes)**
Builds made before 2026-10-29 compiled hpcups without `-DAPDK_LITTLE_ENDIAN`, which
HPLIP's own `configure` always sets. Without it the driver reads the red channel from
the wrong byte of every pixel and the Ernie colour filter turns the whole page black.
Rebuild and reinstall:
```bash
git pull && ./build.sh
sudo ./install.sh            # copies the new filter; add --legacy for Photosmart A-series
```
For photo printers, also match the paper loaded and print JPEGs scaled to the page:
```bash
lpoptions -p <queue> -o media=Photo4x6.FB -o MediaType=Glossy
lp -d <queue> -o fit-to-page photo.jpg
```
Leave `MediaType` on `Automatic` and hpcups tells the printer it has plain paper, which
photo-only printers reject with "Paper size or type is incorrect".

**Older PCL3GUI photo printers (Photosmart A-series, "PSP470" class)**
HP never drove these with hpcups; they shipped with the older `hpijs` driver, whose job
stream differs from hpcups' in several details (raster descriptor, colour-space command,
quality code, row addressing, page end). `install.sh --legacy` makes hpcups reproduce
the hpijs stream. A Photosmart A620 printed correctly from a stream generated by hpijs
itself; whether the plain hpcups stream also works on it is still being tested.

**Printer pulls paper then stalls forever**
That's the generic PCL5 driver, not this one. Remove the old auto-created queue and
reinstall with `install.sh`.

**Filter fails with a library "not found" error**
CUPS sandboxes filters, so a filter linked against a Homebrew dylib can't load it.
`build.sh` handles this by bundling `libjpeg` at `@loader_path` — rerun it.

**Nothing prints and there is no error at all**
Check ink and that the printer isn't mid-setup. Print a self-test from the printer's own
front panel (on many Smart Tanks: hold **Resume** 3 seconds, then press **Resume**). If
the self-test is blank, it's the printer, not the driver.

---

## Notes on the build

Three parts of HPLIP are Linux-only and are handled explicitly:

| Component | Handling | Consequence |
|---|---|---|
| `hpmud` (HP's USB layer) | stub header; CUPS' own `usb` backend does the I/O | none |
| D-Bus status channel | compiled out (`HAVE_DBUS` undefined) | no ink / status reporting |
| `libImageProcessor` | no-op stub — HP ships it as a Linux-only binary | raster passes through unmodified |

Five details worth knowing if you adapt this:

- **`-DAPDK_LITTLE_ENDIAN` is not optional.** HPLIP's `configure` sets it on every
  little-endian machine. hpcups has no runtime detection: without the define,
  `CommonDefinitions.h`, `ErnieFilter.h` and `Mode9.cpp` compile their big-endian
  pixel accessors, which read red from the always-zero top byte of a 24-bit pixel.
  The filter still runs, produces a plausible-looking job, and prints solid black.

- **macOS has no `<malloc.h>`.** `genJPEGStrips.cpp` includes it; `shim/malloc.h`
  stands in and just pulls `<stdlib.h>`.
- **The default filesystem is case-insensitive.** HPLIP has both `common/utils.h` and
  `prnt/hpcups/Utils.h`. On Linux `#include "utils.h"` reaches the former; on APFS it
  silently resolves to the latter and `getHPLogLevel` / `CUPS_TMP_DIR` go undeclared.
  `build.sh` force-includes `common/utils.h` to sidestep this.

- **The filter cannot live in `/usr/libexec/cups/filter`.** SIP makes it read-only. It
  goes in `/Library/Printers/`, and the PPD refers to it by absolute path in
  `cupsFilter`, which CUPS accepts.
- **CUPS sandboxes filters**, so a filter linked against a Homebrew dylib fails at run
  time. `build.sh` copies `libjpeg` beside the binary and rewrites the load path to
  `@loader_path`.

`build.sh` also applies the patches in `patches/` to the HPLIP tree (skipping any that
are already applied). Currently there is one, and it changes nothing unless a PPD opts
in: `*HPLegacyPcl3Gui2: True` (added by `install.sh --legacy`) makes the `pcl3gui2`
encapsulator reproduce the job stream `hpijs` sent to these printers, and
`*HPCrdType: "both"` (`install.sh --krgb`) changes only the raster descriptor. The
patch header lists exactly what differs.

## Limitations

- No ink level or printer status reporting (D-Bus channel stubbed).
- Print only — scanning is not covered.
- Built and tested on Apple Silicon only.

## Licensing

No HP code or binaries are redistributed here; HPLIP is downloaded and compiled on your
machine. See [LICENSE-NOTES.md](LICENSE-NOTES.md).
