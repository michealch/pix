IMAGE ?= pix-builder
DOCKER_CONTEXT ?= dietpi
DOCKER ?= docker --context $(DOCKER_CONTEXT)
REMOTE_HOST ?= dietpi
REMOTE_ROOT ?= /home/dietpi/projects/pix
PROJ ?= $(REMOTE_ROOT)/pix_esp8266
HOST_UID ?= 1000
HOST_GID ?= 1000
PIO_VERSION ?= 6.1.18
DEVICE ?= /dev/ttyUSB0
DEVICE_FLAGS ?= --privileged --device=$(DEVICE)
UPLOAD_DEVICE ?= /dev/ttyACM0
UPLOAD_DEVICE_FLAGS ?= --privileged -u root:root --device=$(UPLOAD_DEVICE)
SYNC_ITEMS ?= Dockerfile .dockerignore Makefile pix_esp8266

.PHONY: image sync fix-perms build upload shell clean

image:
	$(DOCKER) build -t $(IMAGE) \
		--build-arg HOST_UID=$(HOST_UID) \
		--build-arg HOST_GID=$(HOST_GID) \
		--build-arg PIO_VERSION=$(PIO_VERSION) \
		.

sync:
	ssh $(REMOTE_HOST) 'mkdir -p $(REMOTE_ROOT)'
	COPYFILE_DISABLE=1 tar --no-xattrs \
		--exclude='.git' \
		--exclude='__MACOSX' \
		--exclude='._*' \
		--exclude='*/._*' \
		--exclude='pix_esp8266/.pio' \
		--exclude='pix_esp8266/.vscode' \
		--exclude='**/.cache' \
		--exclude='**/compile_commands.json' \
		-cf - $(SYNC_ITEMS) | ssh $(REMOTE_HOST) 'tar -xf - -C $(REMOTE_ROOT)'
	ssh $(REMOTE_HOST) 'find $(REMOTE_ROOT) -name "._*" -delete'

fix-perms:
	$(DOCKER) run --rm --user root -v $(PROJ):/workspace \
		$(IMAGE) chown -R $(HOST_UID):$(HOST_GID) /workspace/.pio

build: sync fix-perms
	$(DOCKER) run --rm -v $(PROJ):/workspace \
		-e WIFI_SSID="$(WIFI_SSID)" \
		-e WIFI_PASS="$(WIFI_PASS)" \
		$(DEVICE_FLAGS) \
		$(IMAGE) platformio run -e tft

upload: sync fix-perms
	$(DOCKER) run --rm -v $(PROJ):/workspace \
		-e WIFI_SSID="$(WIFI_SSID)" \
		-e WIFI_PASS="$(WIFI_PASS)" \
		$(UPLOAD_DEVICE_FLAGS) \
		$(IMAGE) platformio run -e tft -t upload

shell:
	$(DOCKER) run --rm -it -v $(PROJ):/workspace \
		-e WIFI_SSID="$(WIFI_SSID)" \
		-e WIFI_PASS="$(WIFI_PASS)" \
		$(IMAGE) bash

clean:
	$(DOCKER) run --rm -v $(PROJ):/workspace \
		-e WIFI_SSID="$(WIFI_SSID)" \
		-e WIFI_PASS="$(WIFI_PASS)" \
		$(IMAGE) platformio run -e tft -t clean
