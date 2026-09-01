# Copyright (c) Meta Platforms, Inc. and affiliates.

FROM ubuntu:26.04

ARG NDK_VERSION=r27d
ARG NDK_DOWNLOAD_SHA256=601246087a682d1944e1e16dd85bc6e49560fe8b6d61255be2829178c8ed15d9

COPY resolute-install-deps.sh /usr/local/bin/resolute-install-deps.sh

RUN set -eux; \
    /usr/local/bin/resolute-install-deps.sh; \
    ndk_archive="android-ndk-${NDK_VERSION}-linux.zip"; \
    mkdir -p /opt/ndk; \
    curl --fail --location --retry 3 \
        --output "/tmp/${ndk_archive}" \
        "https://dl.google.com/android/repository/${ndk_archive}"; \
    printf '%s  %s\n' "${NDK_DOWNLOAD_SHA256}" "/tmp/${ndk_archive}" \
        | sha256sum --check --status; \
    unzip -q "/tmp/${ndk_archive}" -d /opt/ndk; \
    test -x "/opt/ndk/android-ndk-${NDK_VERSION}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"; \
    rm -f "/tmp/${ndk_archive}"; \
    rm -rf /var/lib/apt/lists/*

ENV NDK_PATH=/opt/ndk/android-ndk-${NDK_VERSION}

WORKDIR /ExtendedAndroidTools

ENTRYPOINT ["/bin/bash"]
