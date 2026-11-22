# PostgreSQL 16 + Patroni + WAL-G (no operator).
# Build: docker build -t postgres-patroni:16 -f docker/Dockerfile .
FROM postgres:16.6-bookworm

ARG PATRONI_VERSION=4.0.4
ARG WALG_VERSION=v3.0.5
ARG KUBECTL_VERSION=v1.32.2

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        curl \
        ca-certificates \
        jq \
        gosu \
        libpq-dev \
        gcc \
    && python3 -m venv /opt/patroni-venv \
    && /opt/patroni-venv/bin/pip install --no-cache-dir \
        "patroni[kubernetes]==${PATRONI_VERSION}" \
        "kubernetes==29.0.0" \
        psycopg2-binary \
        boto3 \
    && curl -fsSL \
        "https://github.com/wal-g/wal-g/releases/download/${WALG_VERSION}/wal-g-pg-ubuntu-20.04-amd64.tar.gz" \
        -o /tmp/wal-g.tar.gz \
    && tar -xzf /tmp/wal-g.tar.gz -C /tmp \
    && mv /tmp/wal-g-pg-ubuntu-20.04-amd64 /usr/local/bin/wal-g \
    && chmod +x /usr/local/bin/wal-g \
    && curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
        -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && /opt/patroni-venv/bin/python -c "import kubernetes, patroni; print('ok', kubernetes.__version__)" \
    && rm -rf /tmp/wal-g.tar.gz /var/lib/apt/lists/* \
    && apt-get purge -y gcc python3-dev \
    && apt-get autoremove -y

ENV PATH="/opt/patroni-venv/bin:${PATH}" \
    PGDATA=/home/postgres/pgdata/data \
    PATRONI_CONFIG_FILE=/etc/patroni/patroni.yml

RUN mkdir -p /home/postgres/pgdata /etc/patroni /home/postgres/scripts \
    && chown -R postgres:postgres /home/postgres /etc/patroni

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/patroni.yml.tpl /etc/patroni/patroni.yml.tpl
RUN chmod +x /usr/local/bin/entrypoint.sh

USER postgres
EXPOSE 5432 8008
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
