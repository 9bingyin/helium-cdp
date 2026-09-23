# docker build -t helium-cdp .
# docker build --build-arg HELIUM_VERSION=0.17.2.1 -t helium-cdp .

FROM bitnami/minideb:trixie AS fetch

ARG HELIUM_VERSION=0.17.2.1

RUN install_packages \
      ca-certificates \
      curl \
      gnupg \
      gpgv \
      xz-utils

COPY image/pubkey.asc /tmp/helium-pubkey.asc

RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
      amd64) helium_arch=x86_64 ;; \
      arm64) helium_arch=arm64 ;; \
      *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    base="https://github.com/imputnet/helium-linux/releases/download/${HELIUM_VERSION}"; \
    file="helium-${HELIUM_VERSION}-${helium_arch}_linux.tar.xz"; \
    curl -fL --retry 5 --retry-delay 2 -o "/tmp/${file}" "${base}/${file}"; \
    curl -fL --retry 5 --retry-delay 2 -o "/tmp/${file}.asc" "${base}/${file}.asc"; \
    gpg --dearmor -o /tmp/helium.gpg /tmp/helium-pubkey.asc; \
    gpgv --keyring /tmp/helium.gpg "/tmp/${file}.asc" "/tmp/${file}"; \
    mkdir -p /opt/helium; \
    tar -xJf "/tmp/${file}" -C /opt/helium --strip-components=1; \
    test -x /opt/helium/helium; \
    test -x /opt/helium/helium-wrapper

FROM bitnami/minideb:trixie

ARG HELIUM_VERSION=0.17.2.1

RUN install_packages \
      ca-certificates \
      curl \
      fontconfig \
      fonts-liberation \
      fonts-noto-cjk \
      fonts-noto-color-emoji \
      libasound2 \
      libatk-bridge2.0-0 \
      libatk1.0-0 \
      libatspi2.0-0 \
      libcairo2 \
      libcups2 \
      libdbus-1-3 \
      libdrm2 \
      libexpat1 \
      libfreetype6 \
      libgbm1 \
      libglib2.0-0 \
      libnspr4 \
      libnss3 \
      libpango-1.0-0 \
      libx11-6 \
      libxcb1 \
      libxcomposite1 \
      libxcursor1 \
      libxdamage1 \
      libxext6 \
      libxfixes3 \
      libxi6 \
      libxkbcommon0 \
      libxrandr2 \
      libxrender1 \
      libxshmfence1 \
      libxss1 \
      libxtst6 \
      libuuid1 \
      socat \
      tini

COPY image/fonts/99-helium-cjk.conf /etc/fonts/conf.d/99-helium-cjk.conf
RUN fc-cache -f

COPY --from=fetch /opt/helium /opt/helium
COPY image/run.sh /opt/helium/run.sh
COPY image/initial_preferences /opt/helium/initial_preferences
COPY image/ublock/default-filter-lists.txt /opt/helium/default-filter-lists.txt
COPY image/ublock/managed_storage.json /opt/helium/resources/ublock/managed_storage.json

RUN chmod 755 /opt/helium/run.sh /opt/helium/helium-wrapper \
 && LD_LIBRARY_PATH="/opt/helium${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" ldd /opt/helium/helium > /tmp/helium-ldd.txt \
 && if grep -q 'not found' /tmp/helium-ldd.txt; then \
      echo "helium is missing shared libraries:" >&2; \
      grep 'not found' /tmp/helium-ldd.txt >&2; \
      exit 1; \
    fi \
 && rm -f /tmp/helium-ldd.txt

RUN install_packages dbus gsettings-desktop-schemas \
 && mkdir -p /run/dbus /var/lib/dbus \
 && dbus-uuidgen --ensure=/etc/machine-id \
 && cp -f /etc/machine-id /var/lib/dbus/machine-id

ENV LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/tmp \
    XDG_CONFIG_HOME=/tmp/xdg-config \
    XDG_CACHE_HOME=/tmp/xdg-cache \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbus/session \
    PATH=/opt/helium:${PATH} \
    HELIUM_VERSION=${HELIUM_VERSION}

LABEL org.opencontainers.image.title="helium-cdp" \
      org.opencontainers.image.description="Headless Helium with Chrome DevTools Protocol and CJK fonts" \
      org.opencontainers.image.source="https://github.com/9bingyin/helium-cdp" \
      org.opencontainers.image.version="${HELIUM_VERSION}"

EXPOSE 9222 9223

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/helium/run.sh"]
