# AGENTS.md

This file is for AI coding agents working in this repository. Read it before
editing. The active user workflow is macOS source editing plus Linux-hosted
Docker builds for an ESP8266 device connected to the Linux host.

## Repository Shape

- Root project: `/Users/michealchoudhary/projects/pix` on macOS.
- Active firmware: `pix_esp8266/`.
- Active PlatformIO environment: `tft`.
- Target board: ESP8266 ESP-12 class board, PlatformIO board `esp12e`.
- Display: ST7789 240x240 TFT through TFT_eSPI.
- Remote Linux build/flash host: Docker context and SSH host `dietpi`.
- Remote synced path: `/home/dietpi/projects/pix`.

Other directories (`pix_ruby/`, `pix_elixir/`, `pix_kernel/`) are historical or
alternate implementations. Do not change them for ESP8266 TFT work unless the
user explicitly asks.

## Source Of Truth And Sync

The macOS checkout is the source of truth. Docker bind mounts with
`docker --context dietpi` resolve paths on the Linux host, not on macOS.

Therefore, never assume that editing a file locally automatically changes what
the Docker build sees. Use the root Makefile targets:

```sh
make build WIFI_SSID="..." WIFI_PASS="..."
make upload WIFI_SSID="..." WIFI_PASS="..."
```

Those targets run `make sync` first, copying the macOS project to
`dietpi:/home/dietpi/projects/pix`.

The sync command intentionally excludes:

- `.git`
- `pix_esp8266/.pio`
- `pix_esp8266/.vscode`
- `__MACOSX`
- `._*` AppleDouble sidecar files
- cache and compile database files

Do not replace this with a naive tar/scp/rsync command unless you preserve those
exclusions. macOS AppleDouble files such as `._pix.cpp` can be compiled by
PlatformIO as source and break the build.

## Build And Upload Commands

Build the Docker image on the Linux Docker host:

```sh
make image
```

Build firmware:

```sh
make build WIFI_SSID="..." WIFI_PASS="..."
```

Upload firmware to the connected ESP:

```sh
make upload WIFI_SSID="..." WIFI_PASS="..."
```

Current upload behavior is intentionally root and privileged inside the
container, with `UPLOAD_DEVICE ?= /dev/ttyACM0` passed through:

```sh
docker --context dietpi run --rm \
  -v /home/dietpi/projects/pix/pix_esp8266:/workspace \
  -e WIFI_SSID="..." \
  -e WIFI_PASS="..." \
  --privileged \
  -u root:root \
  --device=/dev/ttyACM0 \
  pix-builder platformio run -e tft -t upload
```

If upload fails because the device path changed, inspect the Linux host:

```sh
ssh dietpi 'ls -l /dev/ttyUSB* /dev/ttyACM* /dev/serial/by-id/* 2>/dev/null'
```

Then override `UPLOAD_DEVICE` or update the Makefile:

```sh
make upload UPLOAD_DEVICE=/dev/ttyUSB0 WIFI_SSID="..." WIFI_PASS="..."
```

## Dockerfile Design

The root `Dockerfile` is multi-stage:

- `base`: Python slim Bookworm, system dependencies, PlatformIO.
- `deps`: copies only `pix_esp8266/platformio.ini` and runs
  `platformio pkg install -e tft`.
- `runtime`: copies the warmed `.platformio` directory and defaults to
  `platformio run -e tft`.

The image intentionally does not copy `pix_esp8266/src`. Source is supplied by
the runtime bind mount after `make sync`.

Keep `platformio.ini` version ranges unless the user explicitly asks to pin or
change them.

## Generated Artifacts And Permissions

The remote generated PlatformIO tree is:

```sh
/home/dietpi/projects/pix/pix_esp8266/.pio
```

Uploads or manual Docker commands may leave generated files owned by root. The
Makefile has `fix-perms`:

```sh
make fix-perms
```

It runs a root container and chowns `/workspace/.pio` to `1000:1000`. The normal
`build` and `upload` targets already depend on `fix-perms`.

Do not commit `.pio`, firmware binaries, build directories, or cache files.

## PlatformIO Configuration

Important file:

```sh
pix_esp8266/platformio.ini
```

Key details:

- `env:tft` uses `platform = espressif8266`.
- `board = esp12e`.
- `framework = arduino`.
- `build_src_filter` includes `src/pix` and `src/tft`.
- Wi-Fi credentials are injected from environment variables:
  `WIFI_SSID` and `WIFI_PASS`.
- Optional API values are also environment-backed:
  `OWM_KEY`, `LASTFM_USER`, and `LASTFM_KEY`.
- TFT_eSPI is configured entirely through `build_flags`; there is no
  `User_Setup.h`.

## Firmware Architecture

The firmware is not a raw TFT_eSPI drawing app at the screen level. Screens draw
to a logical 16x16 dot grid through the `Platform` interface.

Important files:

- `pix_esp8266/src/pix/platform.h`: platform abstraction.
- `pix_esp8266/src/pix/screen.h`: screen base class and palette values.
- `pix_esp8266/src/pix/pix.cpp`: screen registry, carousel order, scheduling.
- `pix_esp8266/src/tft/tft.cpp`: TFT implementation, dot-grid scaling, Wi-Fi,
  time, OTA.
- `pix_esp8266/src/pix/chars.cpp`: 3x7 logical grid font.
- `pix_esp8266/src/pix/screens/`: individual screens.

Palette values in `screen.h`:

```cpp
BLACK=0, RED=1, GREEN=2, YELLOW=3, BLUE=4, PURPLE=5, CYAN=6, WHITE=7
```

TFT mapping:

- The logical grid is 16x16.
- Each logical dot is drawn as a 15px square on the 240x240 panel.
- `TFT::draw()` only redraws changed logical dots.

## Screen Scheduling

`Pix::step()` is frame based:

- It increments a frame counter.
- It advances to the next screen after `screen_frames`.
- It calls the active screen's `update()` when `frame % throttle == 0`.
- It calls `platform->draw()` every loop.

Follow the existing idiom:

- Use `throttle` to slow animations.
- Do not put `delay()` in screens.
- Do not use `millis()` inside screens unless you are intentionally changing the
  scheduling model.
- Use `platform->clear()` and `platform->set_dot()`.

## TFT Startup And Freeze Notes

`TFT::setup_tft()` should run before Wi-Fi setup so the display initializes even
if networking is bad. `TFT::draw()` must avoid unsigned underflow when pacing
frames; if elapsed time is greater than the target frame time, do not delay.

If the screen is black after flashing, inspect these first:

- Was the firmware built from the synced macOS source?
- Did `make build` or `make upload` succeed after sync?
- Is the flashed binary the one under the remote `.pio/build/tft/` path?
- Does the display initialize before Wi-Fi?
- Is `TFT_BACKLIGHT` still correct for the board?
- Is the device actually booting, or stuck in Wi-Fi/time setup?

## Adding Or Editing Screens

Screens should follow the established pattern:

- Header and implementation in `pix_esp8266/src/pix/screens/`.
- Inherit from `Screen`.
- Store the `Platform *` in the same style as existing screens.
- Register the screen in `pix_esp8266/src/pix/pix.cpp`.
- Add it to `screens_order` if it should appear in the carousel.

Use established helpers:

- `Chars::put_char(platform, c, x, y, color)` for text.
- Inline `std::bitset` sprites for small bitmap art.
- Bounds-check custom `set_dot` loops when drawing off-screen or scrolling.

Avoid:

- Raw TFT_eSPI sprite rendering from screens.
- RGB565 colors in screen code.
- Blocking delays in screen code.
- Large dynamic allocations in `update()`.

## Marquee Screen Notes

The marquee screen is in:

```sh
pix_esp8266/src/pix/screens/marquee.h
pix_esp8266/src/pix/screens/marquee.cpp
```

It scrolls right-to-left in dot-grid units:

- Draw content at `offset`.
- Draw content again at `offset + content_width + GAP_PX`.
- Decrement `offset`.
- Wrap when the content plus gap has fully moved off-screen.

Speed is controlled with `throttle` and `SCROLL_STEP`. Smaller throttle is
faster; larger throttle is slower.

## Code Style

- Keep C++ compatible with the current PlatformIO/Arduino toolchain and existing
  `-std=c++11` setting.
- Prefer the local style over broad refactors.
- Keep edits scoped to the user's request.
- Use ASCII unless there is a strong reason not to.
- Do not commit secrets, Wi-Fi credentials, API keys, firmware binaries, or
  generated PlatformIO directories.

## Verification Checklist For Agents

After firmware changes:

1. Run `make build WIFI_SSID="..." WIFI_PASS="..."` from the macOS checkout.
2. Confirm the build succeeds for `env:tft`.
3. Review warnings and call out any new ones.
4. If flashing is requested, run `make upload WIFI_SSID="..." WIFI_PASS="..."`
   only when the Linux serial device path is known and present.
5. If upload fails, check `/dev/ttyUSB*`, `/dev/ttyACM*`, and
   `/dev/serial/by-id/*` on `dietpi`.

When reporting results, mention that build/upload happened through the Linux
Docker context, not a local macOS PlatformIO install.
