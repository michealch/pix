# PIX

<p align="center">
    <picture>
        <img src="https://github.com/fazibear/pix/blob/master/images/logo.jpg?raw=true" width="250" height="250" alt="PIX">
    </picture>
    <br>
    <strong>Pixel Frame</strong>
</p>

PIX is an ESP8266 pixel-frame firmware project. The active firmware lives in
`pix_esp8266/`; the `tft` PlatformIO environment targets an ESP-12 class board
driving an ST7789 240x240 TFT panel through TFT_eSPI.

The repository also contains older or alternate implementations in
`pix_ruby/`, `pix_elixir/`, and `pix_kernel/`. They are not part of the
ESP8266 TFT build described below.

## Requirements

For the Docker workflow:

- Docker
- GNU Make
- A shell with `tar`

For flashing over USB:

- The ESP8266 connected to the machine that runs Docker
- A visible serial device such as `/dev/ttyUSB0`, `/dev/ttyACM0`, or a
  `/dev/serial/by-id/...` path

No host Python or host PlatformIO install is required.

## Quick Start

Build the dependency-cached PlatformIO image:

```sh
make image
```

Build firmware:

```sh
make build WIFI_SSID="your-wifi" WIFI_PASS="your-password"
```

The firmware binary is created at:

```sh
pix_esp8266/.pio/build/tft/firmware.bin
```

Flash firmware:

```sh
make upload WIFI_SSID="your-wifi" WIFI_PASS="your-password"
```

If your serial device is not `/dev/ttyUSB0`, override it:

```sh
make upload UPLOAD_DEVICE=/dev/ttyACM0 WIFI_SSID="your-wifi" WIFI_PASS="your-password"
```

Useful device discovery command:

```sh
ls -l /dev/ttyUSB* /dev/ttyACM* /dev/serial/by-id/* 2>/dev/null
```

## Optional Remote Docker Host

The default Makefile workflow builds from the local checkout and local Docker
context. If Docker and the ESP device are attached to another machine, use the
optional remote mode.

Example:

```sh
make image DOCKER_CONTEXT=my-linux-box \
  REMOTE_HOST=my-linux-box \
  REMOTE_ROOT=/home/user/projects/pix

make build DOCKER_CONTEXT=my-linux-box \
  REMOTE_HOST=my-linux-box \
  REMOTE_ROOT=/home/user/projects/pix \
  WIFI_SSID="your-wifi" WIFI_PASS="your-password"

make upload DOCKER_CONTEXT=my-linux-box \
  REMOTE_HOST=my-linux-box \
  REMOTE_ROOT=/home/user/projects/pix \
  UPLOAD_DEVICE=/dev/ttyACM0 \
  WIFI_SSID="your-wifi" WIFI_PASS="your-password"
```

When `REMOTE_HOST` is set, `make sync` copies the local checkout to
`REMOTE_ROOT` before build/upload. The sync excludes `.git`, generated
PlatformIO output, editor files, caches, and host metadata sidecar files.

## Make Targets

- `make image` builds the Docker builder image.
- `make sync` is a no-op for local builds, or syncs to `REMOTE_HOST` when set.
- `make fix-perms` repairs generated `.pio` ownership after privileged uploads
  or manual Docker commands.
- `make build WIFI_SSID=... WIFI_PASS=...` builds `env:tft`.
- `make upload WIFI_SSID=... WIFI_PASS=...` builds and flashes `env:tft`.
- `make shell` opens a shell inside the builder container.
- `make clean` runs PlatformIO clean for `env:tft`.

Important Makefile variables:

```make
IMAGE ?= pix-builder
DOCKER_CONTEXT ?= default
REMOTE_HOST ?=
REMOTE_ROOT ?= ~/projects/pix
LOCAL_PROJ ?= $(CURDIR)/pix_esp8266
DEVICE ?= /dev/ttyUSB0
UPLOAD_DEVICE ?= $(DEVICE)
PIO_VERSION ?= 6.1.18
```

## Docker Images

The root `Dockerfile` builds the PlatformIO builder image.

It has three stages:

- `base`: Python, system dependencies, PlatformIO, and a non-root builder user.
- `deps`: copies only `pix_esp8266/platformio.ini` and pre-installs the `tft`
  dependencies.
- `runtime`: contains the warmed PlatformIO cache and defaults to
  `platformio run -e tft`.

`Dockerfile.firmware` is used by CI to publish a minimal firmware artifact image.
It is `FROM scratch` and contains only:

```text
/firmware.bin
```

## Firmware Configuration

The PlatformIO project is in:

```sh
pix_esp8266/platformio.ini
```

The `tft` environment uses:

- `platform = espressif8266`
- `board = esp12e`
- `framework = arduino`
- `bodmer/TFT_eSPI`
- `arduino-libraries/NTPClient`
- `jchristensen/Timezone`

TFT_eSPI is configured through PlatformIO `build_flags`; there is no
`User_Setup.h`.

Wi-Fi credentials are passed as environment variables:

```sh
WIFI_SSID="your-wifi"
WIFI_PASS="your-password"
```

Optional network screen values:

```sh
OWM_KEY="..."
LASTFM_USER="..."
LASTFM_KEY="..."
```

These values are compiled into `firmware.bin`. Do not publish firmware builds
that contain private credentials.

## Firmware Architecture

The TFT firmware uses a logical 16x16 dot grid:

- Screens write pixels with `Platform::set_dot(x, y, color)`.
- Colors are palette values from `pix_esp8266/src/pix/screen.h`.
- `pix_esp8266/src/tft/tft.cpp` maps each dot to a 15px square on the 240x240
  panel.
- `pix_esp8266/src/pix/pix.cpp` handles screen order and frame/throttle
  scheduling.

Screens should use the `Platform` abstraction and the palette. Avoid raw
TFT_eSPI drawing from screen code unless you are intentionally changing the
rendering model.

Palette:

```cpp
BLACK=0, RED=1, GREEN=2, YELLOW=3, BLUE=4, PURPLE=5, CYAN=6, WHITE=7
```

## Screens

Screens live in:

```sh
pix_esp8266/src/pix/screens/
```

They are registered in:

```sh
pix_esp8266/src/pix/pix.cpp
```

The marquee screen scrolls right-to-left in dot-grid units by drawing the
content twice with an offset and wrapping when the content plus gap leaves the
screen.

## GitHub Release Pipeline

The workflow is:

```sh
.github/workflows/firmware-release.yml
```

It runs on every pushed commit:

- Every push runs a Gitleaks secret scan.
- Pushes to the default branch run the release job unless the commit is a release
  commit or contains `[skip release]`.

The release job:

1. Uses `git-cliff` and Conventional Commit messages to calculate the next tag.
2. Generates release notes and prepends `CHANGELOG.md`.
3. Commits the changelog as `chore(release): prepare vX.Y.Z [skip release]`.
4. Builds `firmware.bin`.
5. Publishes a firmware-only image to GitHub Container Registry.
6. Pushes the git tag.
7. Creates a GitHub Release and attaches `firmware.bin`.

Image names:

```text
ghcr.io/<owner>/<repo>/firmware:<tag>
ghcr.io/<owner>/<repo>/firmware:latest
```

Use Conventional Commit messages:

```text
feat: add new screen
fix: prevent display freeze
docs: update build instructions
ci: add release pipeline
```

Breaking changes:

```text
feat!: change firmware configuration layout
```

### GitHub Settings

The workflow uses `GITHUB_TOKEN` to push the changelog commit, push tags, publish
to GHCR, and create releases. Repository Actions settings must allow read/write
permissions for contents and packages.

If the default branch is protected, allow GitHub Actions to push the generated
release commit and tag, or change the workflow to open a release pull request.

### CI Variables And Secrets

The CI build can use:

```text
FIRMWARE_WIFI_SSID   repository variable, optional
FIRMWARE_WIFI_PASS   repository secret, optional
OWM_KEY              repository secret, optional
LASTFM_USER          repository variable, optional
LASTFM_KEY           repository secret, optional
```

If Wi-Fi values are not configured, CI uses placeholder credentials so the
firmware can still compile. Real credentials are embedded into the release
binary and container image, so use them only when that distribution model is
acceptable.

## Troubleshooting

Build cannot remove or overwrite `.pio` files:

```sh
make fix-perms
```

No serial device found:

```sh
ls -l /dev/ttyUSB* /dev/ttyACM* /dev/serial/by-id/* 2>/dev/null
```

Then pass the device explicitly:

```sh
make upload UPLOAD_DEVICE=/dev/ttyACM0 WIFI_SSID="your-wifi" WIFI_PASS="your-password"
```

Display stays black after flashing:

- Confirm the flashed file is the newly built `pix_esp8266/.pio/build/tft/firmware.bin`.
- Confirm the display wiring and TFT build flags match your board.
- Confirm `TFT_BACKLIGHT` in `pix_esp8266/src/tft/tft.h` matches your hardware.
- Confirm Wi-Fi credentials are valid; the firmware initializes TFT before Wi-Fi,
  but network screens still depend on connectivity.

Known warnings:

- `Pix::next_screen()` may warn about signed/unsigned comparison.
- TFT_eSPI may warn that `TOUCH_CS` is not defined; touch is not used.

## Generated Release Files

- `CHANGELOG.md` is generated by git-cliff in CI.
- `cliff.toml` controls git-cliff parsing, grouping, and version bump behavior.
- `Dockerfile.firmware` packages the final firmware artifact into a minimal
  container image.
