# keycloak project image
# Lab image for local Keycloak authorization testing.

ARG KEYCLOAK_VERSION=26.5.6
FROM quay.io/keycloak/keycloak:${KEYCLOAK_VERSION} AS keycloakdist

FROM zzjas/anypoc-base:latest

USER 0

ARG PLAYGROUND_UID=1000
ARG PLAYGROUND_GID=1000
ARG CODEX_CLI_VERSION=0.159.3

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    git \
    jq \
    openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# GPT-5.6 Luna requires a newer Codex CLI than the base image provides.
RUN /opt/node/bin/npm install -g "@openai/codex@${CODEX_CLI_VERSION}" && \
    /opt/node/bin/codex --version

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

RUN install -d -o playground -g playground \
    /home/playground \
    /opt/keycloak \
    /opt/keycloak-source \
    /opt/keycloak-data \
    /opt/keycloak-lab/scripts \
    /var/log/keycloak

COPY --from=keycloakdist /opt/keycloak/ /opt/keycloak/

COPY projects/keycloak/scripts/20-keycloak-services.sh /docker-entrypoint.d/20-keycloak-services.sh
COPY projects/keycloak/scripts/keycloak_status.sh /opt/keycloak-lab/scripts/keycloak_status.sh
COPY projects/keycloak/scripts/seed_lab.sh /opt/keycloak-lab/scripts/seed_lab.sh

RUN chmod 755 /docker-entrypoint.d/20-keycloak-services.sh \
    /opt/keycloak-lab/scripts/keycloak_status.sh \
    /opt/keycloak-lab/scripts/seed_lab.sh && \
    chown -R playground:playground /opt/keycloak /opt/keycloak-source /opt/keycloak-data /opt/keycloak-lab /var/log/keycloak /home/playground

USER playground
WORKDIR /opt/keycloak-source

ARG KEYCLOAK_SOURCE_TAG=26.5.6
RUN install -d \
    services/src/main/java/org/keycloak/authorization/protection/policy \
    services/src/main/java/org/keycloak/authorization/protection \
    testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz && \
    curl -fsSL "https://raw.githubusercontent.com/keycloak/keycloak/refs/tags/${KEYCLOAK_SOURCE_TAG}/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java" \
      -o services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java && \
    curl -fsSL "https://raw.githubusercontent.com/keycloak/keycloak/refs/tags/${KEYCLOAK_SOURCE_TAG}/services/src/main/java/org/keycloak/authorization/protection/ProtectionService.java" \
      -o services/src/main/java/org/keycloak/authorization/protection/ProtectionService.java && \
    curl -fsSL "https://raw.githubusercontent.com/keycloak/keycloak/refs/tags/${KEYCLOAK_SOURCE_TAG}/testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java" \
      -o testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java

USER 0
ARG CAW_STDERR_PATCH=20260826a
RUN /opt/anypoc/.venv/bin/python -c "from pathlib import Path; import caw.providers.codex as codex; p = Path(codex.__file__); t = p.read_text(); old = 'stderr=subprocess.PIPE,'; new = 'stderr=subprocess.DEVNULL,'; assert old in t, f'{old} not found in {p}'; p.write_text(t.replace(old, new, 1)); u = p.read_text(); assert 'stderr=subprocess.DEVNULL,' in u, f'patch did not stick in {p}'; assert 'stderr=subprocess.PIPE,' not in u, f'pipe variant still present in {p}'"

RUN test -x /opt/keycloak/bin/kc.sh && \
    test -x /opt/keycloak/bin/kcadm.sh && \
    test -f /opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java && \
    test -x /opt/keycloak-lab/scripts/keycloak_status.sh

WORKDIR /opt/keycloak
CMD ["/bin/bash"]
