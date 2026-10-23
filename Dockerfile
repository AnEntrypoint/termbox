FROM lscr.io/linuxserver/webtop:ubuntu-xfce

COPY docker/99-gmweb-startup.sh /custom-cont-init.d/99-gmweb-startup.sh
COPY docker/custom_startup.sh /custom-cont-init.d/custom_startup.sh
COPY docker/nginx-setup.sh /custom-cont-init.d/nginx-setup.sh
COPY docker/nginx-sites-enabled-default /custom-cont-init.d/nginx-sites-enabled-default
COPY docker/rest-of-startup.sh /custom-cont-init.d/rest-of-startup.sh
COPY docker/background-installs.sh /custom-cont-init.d/background-installs.sh
RUN chmod +x /custom-cont-init.d/99-gmweb-startup.sh && \
    chmod -x /custom-cont-init.d/custom_startup.sh \
             /custom-cont-init.d/nginx-setup.sh \
             /custom-cont-init.d/rest-of-startup.sh \
             /custom-cont-init.d/background-installs.sh

COPY docker/s6-overlay-mods/ /
RUN chmod +x /etc/s6-overlay/s6-rc.d/svc-selkies/run

# Selkies transport. WebRTC carries media over UDP straight to the client, bypassing the
# HTTP proxy (Coolify Traefik / nginx); WebSockets carries it over the proxied HTTPS port.
# The boxone deployment sits behind a SonicWALL that forwards no inbound UDP rule, so the
# only way UDP reaches this host is a mapping the host opens itself by sending first. That
# is what full ICE does, so WebRTC works without a firewall change — WebSockets stays
# available as the fallback, and SELKIES_ENABLE_DUAL_MODE lets either side switch at runtime
# (POST /desk/api/switch {"mode":"webrtc"|"websockets"}).
# SELKIES_WEBRTC_UDP_MUX_PORT must be published as udp on the host (see docker-compose.yaml).
# SELKIES_WEBRTC_PUBLIC_IP must be the host's public IP when behind 1:1 NAT. svc-selkies/run
# autodetects it when the operator leaves it blank, so WebRTC host candidates name an
# address the client can actually reach rather than the container's private IP.
# SELKIES_WEBRTC_ICE_LITE is false on purpose — see the note in svc-selkies/run. A lite
# agent never sends checks, so it never opens the mapping the firewall requires.
# Direct path by default: rtc.json is STUN-only, so no relay is offered unless TURN is
# switched on. Precedence matters here — Selkies resolves its RTC config in the order
# Cloudflare TURN, this file, TURN REST, legacy TURN, HMAC TURN, built-in STUN default, and
# the first source that yields a config wins. So this file does override the legacy TURN
# options, but Cloudflare TURN is tried ahead of it and still takes effect when enabled.
COPY docker/selkies/rtc.json /etc/selkies/rtc.json
ENV SELKIES_MODE=webrtc \
    SELKIES_ENABLE_DUAL_MODE=true \
    SELKIES_WEBRTC_UDP_MUX_PORT=59000 \
    SELKIES_WEBRTC_ICE_LITE=false \
    SELKIES_RTC_CONFIG_JSON=/etc/selkies/rtc.json

# Office layer: Claude Code, freddie (agent harness) and gridcraft, baked in at build time.
# Installed under /opt/office and linked into /usr/bin: the startup scripts replace /usr/local
# with /config/usr/local, which would hide anything installed there.
# Node 24 LTS from the official tarball, checksum-verified. The apt packages conflict with each other.
ARG NODE_VERSION=24.22.1
RUN cd /tmp \
    && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz" \
    && curl -fsSL -o SHASUMS256.txt "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" \
    && grep " node-v${NODE_VERSION}-linux-x64.tar.gz\$" SHASUMS256.txt | sha256sum -c - \
    && mkdir -p /opt/office/node \
    && tar -xzf "node-v${NODE_VERSION}-linux-x64.tar.gz" -C /opt/office/node --strip-components=1 \
    && rm -f "node-v${NODE_VERSION}-linux-x64.tar.gz" SHASUMS256.txt \
    && ln -sf /opt/office/node/bin/node /usr/bin/node \
    && ln -sf /opt/office/node/bin/npm /usr/bin/npm \
    && ln -sf /opt/office/node/bin/npx /usr/bin/npx
# OFFICE_REFRESH changes on every scheduled CI build, so the install layers below are rebuilt
# and pick up the latest Claude Code and gridcraft release.
ARG OFFICE_REFRESH=0
RUN echo "office refresh ${OFFICE_REFRESH}" \
    && npm install --prefix /opt/office @anthropic-ai/claude-code pnpm@11.7.0 \
    && ln -sf /opt/office/node_modules/.bin/claude /usr/bin/claude \
    && ln -sf /opt/office/node_modules/.bin/pnpm /usr/bin/pnpm
RUN git clone --depth 1 https://github.com/AnEntrypoint/freddie /opt/office/freddie \
    && cd /opt/office/freddie \
    && pnpm install --frozen-lockfile \
    && node -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit(a>22||(a===22&&b>=19)?0:1)'
RUN url=$(curl -fsSL https://api.github.com/repos/storytold/gridcraft/releases/latest \
        | jq -r '.assets[] | select(.name | test("linux-x86_64[.]deb$")) | .browser_download_url') \
    && curl -fsSL -o /tmp/gridcraft.deb "$url" \
    && apt-get update && apt-get install -y /tmp/gridcraft.deb \
    && rm -rf /tmp/gridcraft.deb /var/lib/apt/lists/*

# Claude Code updates come from a new image, not in-place, so every box stays on the same build.
ENV DISABLE_AUTOUPDATER=1

COPY docker/office/office-setup.sh /custom-cont-init.d/98-office-setup.sh
RUN chmod +x /custom-cont-init.d/98-office-setup.sh

EXPOSE 80 443 59000/udp
