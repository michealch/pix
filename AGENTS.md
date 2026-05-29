# AGENTS.md

This file is for AI coding agents working in this repository. Read it before
editing. Keep the project usable by public contributors: avoid machine-specific
paths, hostnames, private Wi-Fi names, or personal workflow assumptions in docs
and scripts.

## Repository Shape

- Active firmware: `pix_esp8266/`.
- Active PlatformIO environment: `tft`.
- Target board: ESP8266 ESP-12 class board, PlatformIO board `esp12e`.
- Display: ST7789 240x240 TFT through TFT_eSPI.
- Historical or alternate implementations: `pix_ruby/`, `pix_elixir/`,
  `pix_kernel/`.

Unless the user explicitly asks otherwise, ESP8266 TFT work should be limited to
the root build files and `pix_esp8266/`.

## Public Usability Rules

- Do not add private hostnames, usernames, absolute personal paths, Wi-Fi names,
  or local network details to committed files.
- Prefer configurable Makefile variables over hardcoded environment details.
- Document examples with placeholder values such as `my-linux-box`,
  `/home/user/projects/pix`, and `your-wifi`.
- Keep local/remote build instructions generic.
- Do not commit firmware binaries, `.pio`, secrets, API keys, or generated
  caches.

## Build Model

The default workflow is local Docker:

```sh
make image
make build WIFI_SSID="..." WIFI_PASS="..."
make upload WIFI_SSID="..." WIFI_PASS="..."
```

The root `Makefile` defaults to:

```make
DOCKER_CONTEXT ?= default
REMOTE_HOST ?=
LOCAL_PROJ ?= $(CURDIR)/pix_esp8266
DEVICE ?= /dev/ttyUSB0
UPLOAD_DEVICE ?= $(DEVICE)
```

When `REMOTE_HOST` is empty, `make sync` is a no-op and Docker bind-mounts the
local `pix_esp8266/` directory.

Optional remote mode is enabled by setting:

```sh
DOCKER_CONTEXT=<docker-context>
REMOTE_HOST=<ssh-host>
REMOTE_ROOT=<remote-project-root>
```

In remote mode, Docker bind mounts are resolved on the remote Docker host, so
`make sync` copies the local checkout to `REMOTE_ROOT` before build/upload.

## Sync Behavior

`make sync` intentionally excludes:

- `.git`
- `pix_esp8266/.pio`
- `pix_esp8266/.vscode`
- `__MACOSX`
- `._*` host metadata sidecar files
- cache and compile database files

Do not replace this with a naive copy command unless the same exclusions are
preserved. Sidecar files such as `._pix.cpp` can be compiled by PlatformIO
as source and break the build.

## Build And Upload Commands

Build the Docker image:

```sh
make image
```

Build firmware:

```sh
make build WIFI_SSID="..." WIFI_PASS="..."
```

Upload firmware:

```sh
make upload WIFI_SSID="..." WIFI_PASS="..."
```

Override the serial device:

```sh
make upload UPLOAD_DEVICE=/dev/ttyACM0 WIFI_SSID="..." WIFI_PASS="..."
```

Inspect serial devices on the machine that runs Docker:

```sh
ls -l /dev/ttyUSB* /dev/ttyACM* /dev/serial/by-id/* 2>/dev/null
```

If Docker needs different serial permissions, override `UPLOAD_DEVICE_FLAGS`.

## Dockerfile Design

The root `Dockerfile` is multi-stage:

- `base`: Python slim Bookworm, system dependencies, PlatformIO, and a non-root
  builder user.
- `deps`: copies only `pix_esp8266/platformio.ini` and runs
  `platformio pkg install -e tft`.
- `runtime`: copies the warmed `.platformio` directory and defaults to
  `platformio run -e tft`.

The image intentionally does not copy `pix_esp8266/src`. Source is provided by a
runtime bind mount.

Keep `platformio.ini` version ranges unless the user explicitly asks to pin or
change them.

The firmware artifact image is built with:

```sh
Dockerfile.firmware
```

It is `FROM scratch` and copies only:

```sh
pix_esp8266/.pio/build/tft/firmware.bin
```

to:

```sh
/firmware.bin
```

The root `.dockerignore` must allow `Dockerfile.firmware` and that exact
firmware path, otherwise the CI image build will fail.

## Generated Artifacts And Permissions

PlatformIO generated output is under:

```sh
pix_esp8266/.pio
```

Privileged uploads or manual Docker commands can leave generated files owned by
root. Use:

```sh
make fix-perms
```

The normal `build` and `upload` targets already depend on `fix-perms`.

Do not commit `.pio`, firmware binaries, build directories, cache files, or
generated compile databases.

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
- Wi-Fi credentials are injected from `WIFI_SSID` and `WIFI_PASS`.
- Optional API values are `OWM_KEY`, `LASTFM_USER`, and `LASTFM_KEY`.
- TFT_eSPI is configured entirely through `build_flags`; there is no
  `User_Setup.h`.

Important: credentials passed through PlatformIO build flags are compiled into
`firmware.bin`. Do not publish firmware containing private credentials.

## Firmware Architecture

The firmware is not a raw TFT_eSPI drawing app at the screen level. Screens draw
to a logical 16x16 dot grid through the `Platform` interface.

Important files:

- `pix_esp8266/src/pix/platform.h`: platform abstraction.
- `pix_esp8266/src/pix/screen.h`: screen base class and palette values.
- `pix_esp8266/src/pix/pix.cpp`: screen registry, carousel order, scheduling.
- `pix_esp8266/src/tft/tft.cpp`: TFT implementation, dot-grid scaling, Wi-Fi,
  time, OTA.
- `pix_esp8266/src/pix/chars.cpp`: logical grid font.
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
- Do not use `millis()` inside screens unless intentionally changing the
  scheduling model.
- Use `platform->clear()` and `platform->set_dot()`.

## TFT Startup And Freeze Notes

`TFT::setup_tft()` should run before Wi-Fi setup so the display initializes even
if networking is unavailable. `TFT::draw()` must avoid unsigned underflow when
pacing frames; if elapsed time is greater than the target frame time, do not
delay.

If the screen is black after flashing, inspect:

- Was the newly built `firmware.bin` flashed?
- Do display wiring and TFT build flags match the board?
- Is `TFT_BACKLIGHT` correct for the hardware?
- Is the device booting, or stuck in Wi-Fi/time setup?

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

## GitHub Actions Release Pipeline

The CI workflow is:

```sh
.github/workflows/firmware-release.yml
```

It runs on every pushed commit. The `secret-scan` job always runs. The `release`
job runs only on the repository default branch and skips commits whose message
starts with `chore(release):` or contains `[skip release]`.

Pipeline responsibilities:

- Run Gitleaks before releasing.
- Use `git-cliff` to calculate the next semantic version from Conventional
  Commit messages.
- Generate `RELEASE_NOTES.md`.
- Prepend release notes to `CHANGELOG.md`.
- Commit the changelog with `chore(release): prepare vX.Y.Z [skip release]`.
- Build the PlatformIO builder image from `Dockerfile`.
- Build `pix_esp8266/.pio/build/tft/firmware.bin`.
- Build `Dockerfile.firmware`, a scratch image containing only `/firmware.bin`.
- Push the image to `ghcr.io/<owner>/<repo>/firmware:<tag>` and `latest`.
- Push the git tag.
- Create a GitHub Release and attach `firmware.bin`.

Do not remove the `[skip release]` marker from the release commit. It prevents a
recursive release when the workflow pushes `CHANGELOG.md`.

The workflow needs:

- `contents: write` for changelog commits, tags, and GitHub Releases.
- `packages: write` for GitHub Container Registry.

If the default branch is protected, the workflow may fail while pushing
`CHANGELOG.md`; either allow GitHub Actions to push release commits or change
the release strategy before merging.

## git-cliff

The config is:

```sh
cliff.toml
```

Use Conventional Commit messages:

```text
feat: add a screen
fix: prevent display freeze
docs: update build instructions
ci: improve release pipeline
```

Breaking changes should use `!` or a `BREAKING CHANGE:` footer. Agents should
not manually edit generated sections in `CHANGELOG.md` unless the user asks.

## Secret Scanning

The workflow uses Gitleaks to detect accidentally committed secrets. Treat a
Gitleaks failure as a real security event:

- Do not silence it with broad allowlist rules.
- Remove the secret from history if it was actually committed.
- Rotate the exposed credential.
- Only add narrow allowlist entries for known false positives.

The firmware build can read these CI values:

```text
FIRMWARE_WIFI_SSID   repository variable
FIRMWARE_WIFI_PASS   repository secret
OWM_KEY              repository secret
LASTFM_USER          repository variable
LASTFM_KEY           repository secret
```

If CI uses real credentials, they are embedded in the release asset and firmware
container image. For public releases, prefer placeholder CI credentials and let
users build personal firmware locally.

## Code Style

- Keep C++ compatible with the current PlatformIO/Arduino toolchain and existing
  `-std=c++11` setting.
- Prefer the local style over broad refactors.
- Keep edits scoped to the user's request.
- Use ASCII unless there is a strong reason not to.
- Do not commit secrets, credentials, API keys, firmware binaries, or generated
  PlatformIO directories.

## Verification Checklist For Agents

After firmware changes:

1. Run `make -n build WIFI_SSID=... WIFI_PASS=...`.
2. Run `make build WIFI_SSID="..." WIFI_PASS="..."` when Docker is available.
3. Confirm the build succeeds for `env:tft`.
4. Review warnings and call out any new ones.
5. If flashing is requested, run `make upload WIFI_SSID="..." WIFI_PASS="..."`
   only when the serial device path is known and present.

After CI/release changes:

1. Parse or inspect `.github/workflows/firmware-release.yml`.
2. Run `make -n build WIFI_SSID=... WIFI_PASS=...`.
3. Run `make -n upload WIFI_SSID=... WIFI_PASS=...`.
4. Confirm `.dockerignore` exposes only files needed by `Dockerfile` and
   `Dockerfile.firmware`.
5. Confirm README and AGENTS mention any new secrets, variables, tags, or
   release artifacts.
