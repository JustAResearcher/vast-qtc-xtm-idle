FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG PEAK_VERSION=2.16.2
ARG PEAK_SHA256=a7ee8c12b47d1de75413cabfa813fb141d4224f882639de3d4dfdfeaeb8f95fc
ARG XMRIG_VERSION=6.26.0
ARG XMRIG_SHA256=fc6f8ae5f64e4f17481f7e3be29a1c56949f216a998414188003eae1db20c9e5

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tini \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /tmp/peakminer.tar.gz \
      "https://github.com/peakminer/peakminer/releases/download/v${PEAK_VERSION}/peakminer-${PEAK_VERSION}.tar.gz" \
    && echo "${PEAK_SHA256}  /tmp/peakminer.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/peakminer.tar.gz -C /opt \
    && mv /opt/peakminer/peakminer /usr/local/bin/peakminer \
    && chmod 0755 /usr/local/bin/peakminer \
    && rm -rf /opt/peakminer /tmp/peakminer.tar.gz \
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
