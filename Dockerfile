FROM nvidia/cuda:12.8.1-runtime-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG SRB_VERSION=3.6.4
ARG SRB_VERSION_SLUG=3-6-4
ARG SRB_SHA256=a6fc1248ad40fba64dc11869d9af34f6ed6d40a2878bd33b9fc062a8a41b92d8
ARG XMRIG_VERSION=6.26.0
ARG XMRIG_SHA256=fc6f8ae5f64e4f17481f7e3be29a1c56949f216a998414188003eae1db20c9e5

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tini \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /tmp/srbminer.tar.gz \
      "https://github.com/doktor83/SRBMiner-Multi/releases/download/${SRB_VERSION}/SRBMiner-Multi-${SRB_VERSION_SLUG}-Linux.tar.gz" \
    && echo "${SRB_SHA256}  /tmp/srbminer.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/srbminer.tar.gz -C /opt \
    && mv "/opt/SRBMiner-Multi-${SRB_VERSION_SLUG}/SRBMiner-MULTI" /usr/local/bin/SRBMiner-MULTI \
    && chmod 0755 /usr/local/bin/SRBMiner-MULTI \
    && rm -rf "/opt/SRBMiner-Multi-${SRB_VERSION_SLUG}" /tmp/srbminer.tar.gz \
    && curl -fsSL -o /tmp/xmrig.tar.gz \
      "https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-linux-static-x64.tar.gz" \
    && echo "${XMRIG_SHA256}  /tmp/xmrig.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/xmrig.tar.gz -C /opt \
    && mv "/opt/xmrig-${XMRIG_VERSION}/xmrig" /usr/local/bin/xmrig \
    && chmod 0755 /usr/local/bin/xmrig \
    && rm -rf "/opt/xmrig-${XMRIG_VERSION}" /tmp/xmrig.tar.gz

COPY entrypoint.sh /usr/local/bin/idle-mining
RUN chmod 0755 /usr/local/bin/idle-mining

LABEL org.opencontainers.image.source="https://github.com/JustAResearcher/vast-qtc-xtm-idle"
LABEL org.opencontainers.image.description="Vast background job for QTC GPU and XTM CPU idle mining"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/idle-mining"]
