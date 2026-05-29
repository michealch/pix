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

## Build Model

The normal development checkout is on macOS, but the ESP device is connected to
a Linux host. The root `Makefile` is set up for that split:

1. Sync the macOS checkout to the Linux host over SSH.
2. Build or upload inside Docker on the Linux host.
3. Use the Linux host's serial device when flashing.

No local Python or PlatformIO install is required on macOS. Docker is required on
the Linux host and must be reachable through the configured Docker context.

Default remote settings:

```make
DOCKER_CONTEXT ?= dietpi
REMOTE_HOST ?= dietpi
REMOTE_ROOT ?= /home/dietpi/projects/pix
PROJ ?= $(REMOTE_ROOT)/pix_esp8266
IMAGE ?= pix-builder
```

## One-Time Image Build

Build the dependency-cached PlatformIO image on the Linux Docker host:

```sh
make image
```

The image is named `pix-builder` by default. It pre-installs PlatformIO and
pre-warms the `tft` environment dependencies from `pix_esp8266/platformio.ini`.

## Build Firmware

From the macOS checkout:

```sh
make build WIFI_SSID="your-wifi" WIFI_PASS="your-password"
```

This syncs the project to `dietpi:/home/dietpi/projects/pix`, fixes generated
`.pio` ownership on the remote host, and runs:

```sh
platformio run -e tft
```

inside the Docker container.

The resulting firmware is on the Linux host at:

```sh
/home/dietpi/projects/pix/pix_esp8266/.pio/build/tft/firmware.bin
```

## Push Firmware

With the ESP connected to the Linux host:

```sh
make upload WIFI_SSID="your-wifi" WIFI_PASS="your-password"
```

The current `upload` target runs PlatformIO upload inside the Linux Docker
context and passes the serial device through to the container:

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

If the ESP appears under another device path on the Linux host, override
`UPLOAD_DEVICE`:

```sh
make upload UPLOAD_DEVICE=/dev/ttyUSB0 WIFI_SSID="your-wifi" WIFI_PASS="your-password"
```

Useful checks on the Linux host:

```sh
ls -l /dev/ttyUSB* /dev/ttyACM* /dev/serial/by-id/* 2>/dev/null
```

## Make Targets

- `make image` builds the Docker image on the configured Docker context.
- `make sync` copies the macOS checkout to the Linux host while excluding `.git`,
  `.pio`, `.vscode`, cache files, and macOS AppleDouble metadata.
- `make fix-perms` repairs ownership of the remote generated `.pio` tree.
- `make build WIFI_SSID=... WIFI_PASS=...` syncs and builds `env:tft`.
- `make upload WIFI_SSID=... WIFI_PASS=...` syncs and flashes `env:tft`.
- `make shell` opens a shell inside the builder container.
- `make clean` runs PlatformIO clean for `env:tft`.

## Firmware Notes

The TFT firmware uses the project's logical 16x16 dot grid:

- Screens write pixels with `Platform::set_dot(x, y, color)`.
- Colors are the palette values in `pix_esp8266/src/pix/screen.h`.
- `pix_esp8266/src/tft/tft.cpp` scales each logical dot to a 15px square.
- Screen scheduling is frame/throttle based in `pix_esp8266/src/pix/pix.cpp`.

Avoid using raw TFT_eSPI drawing APIs inside screens unless the rendering model
is intentionally being changed.

## Screens

Screens live in `pix_esp8266/src/pix/screens/` and are registered in
`pix_esp8266/src/pix/pix.cpp`.

The marquee screen is implemented in the same dot-grid idiom. It scrolls
right-to-left by clearing the logical grid, drawing content twice with an offset,
then decrementing the offset according to its throttle.

## Troubleshooting

If the display stays black after flashing:

- Confirm the firmware was built from the macOS source you edited. `make build`
  performs this sync automatically.
- Confirm the flashed binary is the remote artifact under
  `/home/dietpi/projects/pix/pix_esp8266/.pio/build/tft/firmware.bin`.
- Check Wi-Fi credentials. TFT setup now runs before Wi-Fi, but network-backed
  screens may still show fallback data if credentials or API keys are missing.
- Check the serial device path on the Linux host before uploading.
- If `.pio` permissions break after a root upload or manual command, run
  `make fix-perms`.

Known build warnings:

- `Pix::next_screen()` has an existing signed/unsigned comparison warning.
- TFT_eSPI warns that `TOUCH_CS` is not defined; touch is not used by this
  firmware.

## Older Subprojects

This repository also contains older or alternate implementations:

- `pix_ruby/`
- `pix_elixir/`
- `pix_kernel/`

They are not part of the ESP8266 TFT Docker build path.
