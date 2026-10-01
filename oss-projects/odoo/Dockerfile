# odoo project image
# Lab image for business-logic and access-control testing against Odoo 15.0.

FROM zzjas/anypoc-base:latest

USER 0

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    postgresql \
    postgresql-client \
    libpq-dev \
    libxml2-dev \
    libxslt1-dev \
    libldap2-dev \
    libsasl2-dev \
    libjpeg-dev \
    zlib1g-dev \
    libffi-dev \
    libyaml-dev \
    libtiff5-dev \
    libopenjp2-7-dev \
    liblcms2-dev \
    libwebp-dev \
    gcc \
    g++ \
    git \
    curl \
    npm \
    node-less \
    && npm install -g rtlcss \
    && rm -rf /var/lib/apt/lists/*

RUN getent group playground >/dev/null || groupadd playground && \
    id -u playground >/dev/null 2>&1 || useradd -m -s /bin/bash -g playground playground

RUN mkdir -p /opt/odoo /opt/odoo-data /opt/odoo-lab/scripts /opt/odoo-venv /var/log/odoo && \
    chown -R playground:playground /opt/odoo /opt/odoo-data /opt/odoo-lab /opt/odoo-venv /var/log/odoo /home/playground

ARG ODOO_CONFIG_PATCH=20260815f
COPY projects/odoo/scripts/odoo.conf /opt/odoo-lab/odoo.conf
COPY projects/odoo/scripts/seed_lab.py /opt/odoo-lab/scripts/seed_lab.py
COPY projects/odoo/scripts/odoo_status.sh /opt/odoo-lab/scripts/odoo_status.sh
COPY projects/odoo/scripts/20-odoo-services.sh /docker-entrypoint.d/20-odoo-services.sh
COPY projects/odoo/scripts/sitecustomize.py /opt/odoo-lab/pycompat/sitecustomize.py
COPY projects/odoo/addons/ /opt/odoo/addons/
RUN chown -R playground:playground /opt/odoo /opt/odoo-lab

RUN chmod 755 /opt/odoo-lab/scripts/odoo_status.sh /docker-entrypoint.d/20-odoo-services.sh

USER playground
WORKDIR /opt/odoo
ENV PYTHONPATH=/opt/odoo-lab/pycompat

ARG ODOO_COMMIT=9a06302
RUN curl -fsSL "https://github.com/odoo/odoo/archive/${ODOO_COMMIT}.tar.gz" | tar -xz --strip-components=1

ARG ODOO_MAIL_PATCH=20260815c
RUN python3 -c "from pathlib import Path; p = Path('/opt/odoo/odoo/addons/base/models/ir_mail_server.py'); t = p.read_text(); old = 'from urllib3.contrib.pyopenssl import PyOpenSSLContext'; new = '''try:\n    from urllib3.contrib.pyopenssl import PyOpenSSLContext\nexcept Exception:\n    PyOpenSSLContext = None'''; assert old in t, f'expected import line not found in {p}'; t = t.replace(old, new, 1); p.write_text(t); u = p.read_text(); assert old not in [line.strip() if line.startswith('    ') else line for line in u.splitlines() if line == old], f'import patch did not stick in {p}'; assert 'except Exception:' in u, f'patched guard missing in {p}'"

RUN python3 -m venv /opt/odoo-venv && \
    /opt/odoo-venv/bin/pip install --upgrade pip wheel "setuptools<81"

ARG ODOO_REQ_PATCH=20260815c
RUN sed -i "s/^Babel==2.6.0$/Babel==2.9.1/" /opt/odoo/requirements.txt && \
    sed -i "s/^gevent==20.9.0.*/gevent==22.10.2 ; python_version >= '3.8'/" /opt/odoo/requirements.txt && \
    sed -i "s/^greenlet==0.4.17.*/greenlet==2.0.2 ; python_version > '3.7'/" /opt/odoo/requirements.txt && \
    sed -i "s/^lxml==4.6.1.*/lxml==4.9.3 ; sys_platform != 'win32' and python_version > '3.7'/" /opt/odoo/requirements.txt && \
    sed -i "s/^pyopenssl==19.0.0$/pyOpenSSL==24.2.1/" /opt/odoo/requirements.txt && \
    sed -i "s/^psutil==5.6.6$/psutil==5.9.8/" /opt/odoo/requirements.txt

RUN grep -E '^(Babel|gevent|greenlet|lxml|psutil|pyOpenSSL|pyopenssl)' /opt/odoo/requirements.txt
RUN /opt/odoo-venv/bin/python -c "import collections; print('compat:Set', hasattr(collections, 'Set'))"
RUN /opt/odoo-venv/bin/pip install -r /opt/odoo/requirements.txt

USER 0
ARG CAW_STDERR_PATCH=20260815a
RUN /opt/anypoc/.venv/bin/python -c "from pathlib import Path; import caw.providers.codex as codex; p = Path(codex.__file__); t = p.read_text(); old = 'stderr=subprocess.PIPE,'; new = 'stderr=subprocess.DEVNULL,'; assert old in t, f'{old} not found in {p}'; p.write_text(t.replace(old, new, 1)); u = p.read_text(); assert 'stderr=subprocess.DEVNULL,' in u, f'patch did not stick in {p}'; assert 'stderr=subprocess.PIPE,' not in u, f'pipe variant still present in {p}'"

RUN set -eux; \
    cluster="$(pg_lsclusters --no-header | awk 'NR==1 {print $1, $2}')"; \
    version="$(echo "$cluster" | awk '{print $1}')"; \
    name="$(echo "$cluster" | awk '{print $2}')"; \
    pg_ctlcluster "$version" "$name" start; \
    su postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='playground'\"" | grep -q 1 || su postgres -c "createuser -s playground"; \
    su postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='anypoc_odoo'\"" | grep -q 1 || su postgres -c "createdb -O playground anypoc_odoo"; \
    runuser -u playground -- /opt/odoo-venv/bin/python /opt/odoo/odoo-bin -c /opt/odoo-lab/odoo.conf -d anypoc_odoo -i web,account,l10n_fr,l10n_fr_fec,anypoc_lab --stop-after-init; \
    runuser -u playground -- bash -lc "/opt/odoo-venv/bin/python /opt/odoo/odoo-bin shell -c /opt/odoo-lab/odoo.conf -d anypoc_odoo < /opt/odoo-lab/scripts/seed_lab.py"; \
    pg_ctlcluster "$version" "$name" stop

RUN test -f /opt/odoo/addons/l10n_fr_fec/wizard/account_fr_fec.py && \
    test -f /opt/odoo/addons/anypoc_lab/models/approval.py && \
    test -x /opt/odoo-venv/bin/python

WORKDIR /opt/odoo
CMD ["/bin/bash"]
