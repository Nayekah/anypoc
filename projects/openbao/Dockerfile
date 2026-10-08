# OpenBao project image for local OIDC authentication testing.

ARG OPENBAO_VERSION=2.5.1
FROM quay.io/openbao/openbao:${OPENBAO_VERSION} AS openbaodist

FROM zzjas/anypoc-base:latest

USER 0

ARG PLAYGROUND_UID=1000
ARG PLAYGROUND_GID=1000
ARG OPENBAO_VERSION=2.5.1
ARG CODEX_CLI_VERSION=0.159.3

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    git \
    jq \
    && rm -rf /var/lib/apt/lists/*

# GPT-5.6 Luna requires a recent Codex CLI. jsdom provides a deterministic,
# local browser-like oracle without downloading packages during an attempt.
RUN /opt/node/bin/npm install -g \
    "@openai/codex@${CODEX_CLI_VERSION}" \
    "jsdom@26.1.0" && \
    /opt/node/bin/codex --version

ENV NODE_PATH=/opt/node/lib/node_modules

RUN if getent group playground >/dev/null; then \
        groupmod -o -g "${PLAYGROUND_GID}" playground; \
    else \
        groupadd -g "${PLAYGROUND_GID}" playground; \
    fi && \
    if id -u playground >/dev/null 2>&1; then \
        usermod -o -u "${PLAYGROUND_UID}" -g "${PLAYGROUND_GID}" playground; \
    else \
        useradd -m -u "${PLAYGROUND_UID}" -g "${PLAYGROUND_GID}" -s /bin/bash playground; \
    fi

COPY --from=openbaodist /bin/bao /usr/local/bin/bao

RUN install -d -o playground -g playground \
    /home/playground \
    /opt/openbao-source \
    /opt/openbao-data \
    /opt/openbao-lab/scripts \
    /var/log/openbao && \
    ln -sf /usr/local/bin/bao /usr/local/bin/vault

RUN git clone --depth 1 --branch "v${OPENBAO_VERSION}" \
    https://github.com/openbao/openbao.git /opt/openbao-source && \
    chown -R playground:playground /opt/openbao-source

COPY projects/openbao/scripts/20-openbao-services.sh /docker-entrypoint.d/20-openbao-services.sh
COPY projects/openbao/scripts/mock_oidc_provider.py /opt/openbao-lab/scripts/mock_oidc_provider.py
COPY projects/openbao/scripts/openbao_status.sh /opt/openbao-lab/scripts/openbao_status.sh
COPY projects/openbao/scripts/seed_lab.sh /opt/openbao-lab/scripts/seed_lab.sh

RUN chmod 755 \
    /docker-entrypoint.d/20-openbao-services.sh \
    /opt/openbao-lab/scripts/mock_oidc_provider.py \
    /opt/openbao-lab/scripts/openbao_status.sh \
    /opt/openbao-lab/scripts/seed_lab.sh && \
    chown -R playground:playground \
    /opt/openbao-data \
    /opt/openbao-lab \
    /var/log/openbao \
    /home/playground

USER 0
ARG CAW_STDERR_PATCH=20260826a
RUN /opt/anypoc/.venv/bin/python -c "from pathlib import Path; import caw.providers.codex as codex; p = Path(codex.__file__); t = p.read_text(); old = 'stderr=subprocess.PIPE,'; new = 'stderr=subprocess.DEVNULL,'; assert old in t, f'{old} not found in {p}'; p.write_text(t.replace(old, new, 1)); u = p.read_text(); assert 'stderr=subprocess.DEVNULL,' in u; assert 'stderr=subprocess.PIPE,' not in u"

RUN test -x /usr/local/bin/bao && \
    test -f /opt/openbao-source/builtin/credential/jwt/path_oidc.go && \
    test -f /opt/openbao-source/builtin/credential/jwt/html_responses.go && \
    test -x /opt/openbao-lab/scripts/openbao_status.sh

WORKDIR /opt/openbao-source
CMD ["/bin/bash"]
