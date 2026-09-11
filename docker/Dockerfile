# Copyright (c) Meta Platforms, Inc. and affiliates.

FROM ubuntu:26.04

ARG NDK_DOWNLOAD_URL
ARG NDK_DOWNLOAD_SHA256

SHELL ["/bin/bash", "-c"]

COPY projects/versions.mk /opt/build-config/projects/versions.mk
COPY scripts/ndk-config.sh /opt/build-config/scripts/ndk-config.sh
COPY scripts/resolute-install-deps.sh /usr/local/bin/resolute-install-deps.sh

RUN set -euxo pipefail; \
    /usr/local/bin/resolute-install-deps.sh; \
    source /opt/build-config/scripts/ndk-config.sh; \
    ndk_host_tag="$(ndk_host_tag)"; \
    ndk_download_defaults "$ndk_host_tag"; \
    ndk_archive="android-ndk-${NDK_VERSION}-linux.zip"; \
    mkdir -p /opt/ndk; \
    curl --fail --location --retry 3 \
        --output "/tmp/${ndk_archive}" \
        "$NDK_DOWNLOAD_URL"; \
    printf '%s  %s\n' "${NDK_DOWNLOAD_SHA256}" "/tmp/${ndk_archive}" \
        | sha256sum --check --status; \
    unzip -q "/tmp/${ndk_archive}" -d /opt/ndk; \
    ndk_validate_revision "/opt/ndk/android-ndk-${NDK_VERSION}"; \
    "/opt/ndk/android-ndk-${NDK_VERSION}/toolchains/llvm/prebuilt/${ndk_host_tag}/bin/clang" --version; \
    ln -s "android-ndk-${NDK_VERSION}" /opt/ndk/current; \
    rm -f "/tmp/${ndk_archive}"; \
    rm -rf /var/lib/apt/lists/*

ENV NDK_PATH=/opt/ndk/current

WORKDIR /ExtendedAndroidTools

ENTRYPOINT ["/bin/bash"]
