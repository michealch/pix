FROM python:3.11-slim-bookworm AS base

ARG HOST_UID=1000
ARG HOST_GID=1000
ARG PIO_VERSION=6.1.18

RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN if ! getent group "${HOST_GID}" >/dev/null; then \
        groupadd --gid "${HOST_GID}" builder; \
    fi \
    && useradd --uid "${HOST_UID}" --gid "${HOST_GID}" --create-home --shell /bin/bash builder

RUN pip install --no-cache-dir "platformio==${PIO_VERSION}"

ENV HOME=/home/builder
ENV PLATFORMIO_CORE_DIR=/home/builder/.platformio

FROM base AS deps

USER builder
WORKDIR /workspace

COPY --chown=builder:builder pix_esp8266/platformio.ini /workspace/platformio.ini
RUN platformio pkg install -e tft

FROM base AS runtime

COPY --from=deps --chown=builder:builder /home/builder/.platformio /home/builder/.platformio

USER builder
WORKDIR /workspace

ENTRYPOINT []
CMD ["platformio", "run", "-e", "tft"]
