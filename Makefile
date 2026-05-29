IMAGE ?= pix-builder
DOCKER_CONTEXT ?= default
DOCKER ?= docker --context $(DOCKER_CONTEXT)
REMOTE_HOST ?=
REMOTE_ROOT ?= ~/projects/pix
LOCAL_PROJ ?= $(CURDIR)/pix_esp8266
PROJ ?= $(if $(REMOTE_HOST),$(REMOTE_ROOT)/pix_esp8266,$(LOCAL_PROJ))
HOST_UID ?= $(shell id -u)
HOST_GID ?= $(shell id -g)
PIO_VERSION ?= 6.1.18
DEVICE ?= /dev/ttyUSB0
DEVICE_FLAGS ?=
UPLOAD_DEVICE ?= $(DEVICE)
UPLOAD_DEVICE_FLAGS ?= --privileged --device=$(UPLOAD_DEVICE)
SYNC_ITEMS ?= Dockerfile .dockerignore Makefile pix_esp8266

.PHONY: image sync fix-perms build upload shell clean

image:
	$(DOCKER) build -t $(IMAGE) \
		--build-arg HOST_UID=$(HOST_UID) \
		--build-arg HOST_GID=$(HOST_GID) \
		--build-arg PIO_VERSION=$(PIO_VERSION) \
		.

sync:
	@if [ -n "$(REMOTE_HOST)" ]; then \
		ssh $(REMOTE_HOST) 'mkdir -p $(REMOTE_ROOT)'; \
		COPYFILE_DISABLE=1 tar --no-xattrs \
			--exclude='.git' \
			--exclude='__MACOSX' \
			--exclude='._*' \
			--exclude='*/._*' \
			--exclude='pix_esp8266/.pio' \
			--exclude='pix_esp8266/.vscode' \
			--exclude='**/.cache' \
			--exclude='**/compile_commands.json' \
			-cf - $(SYNC_ITEMS) | ssh $(REMOTE_HOST) 'tar -xf - -C $(REMOTE_ROOT)'; \
		ssh $(REMOTE_HOST) 'find $(REMOTE_ROOT) -name "._*" -delete'; \
	else \
		printf 'REMOTE_HOST is empty; using local project at %s\n' '$(LOCAL_PROJ)'; \
	fi

fix-perms:
	@if [ -d "$(if $(REMOTE_HOST),,$(LOCAL_PROJ)/.pio)" ] || [ -n "$(REMOTE_HOST)" ]; then \
		$(DOCKER) run --rm --user root -v $(PROJ):/workspace \
			$(IMAGE) sh -c 'if [ -d /workspace/.pio ]; then chown -R $(HOST_UID):$(HOST_GID) /workspace/.pio; fi'; \
	fi

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
