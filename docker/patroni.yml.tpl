# NOTE: For Kubernetes DCS, top-level "namespace" must be the K8s namespace
# without leading/trailing slashes (unlike etcd-style /service/ paths).
scope: __SCOPE__
name: __NAME__
namespace: __NAMESPACE__

restapi:
  listen: 0.0.0.0:8008
  connect_address: __POD_IP__:8008

kubernetes:
  namespace: __NAMESPACE__
  use_endpoints: false
  labels:
    app: postgres-ha
    cluster-name: __SCOPE__
  pod_ip: __POD_IP__

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      remove_data_directory_on_rewind_failure: true
      remove_data_directory_on_diverged_timelines: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_connections: 100
        max_wal_senders: 10
        max_replication_slots: 10
        wal_keep_size: 128MB
        max_slot_wal_keep_size: 1GB
        hot_standby_feedback: "on"
        archive_mode: "on"
        archive_command: "wal-g wal-push %p"
        archive_timeout: 60s
  initdb:
    - encoding: UTF8
    - locale: en_US.UTF-8
    - data-checksums
  pg_hba:
    - local all all trust
    - host all all 0.0.0.0/0 md5
    - host replication replicator 0.0.0.0/0 md5
  users:
    admin:
      password: __ADMIN_PASSWORD__
      options:
        - createrole
        - createdb

postgresql:
  listen: 0.0.0.0:5432
  connect_address: __POD_IP__:5432
  data_dir: /home/postgres/pgdata/data
  bin_dir: /usr/lib/postgresql/16/bin
  pgpass: /home/postgres/.pgpass
  authentication:
    replication:
      username: replicator
      password: __REPLICATOR_PASSWORD__
    superuser:
      username: postgres
      password: __SUPERUSER_PASSWORD__
  parameters:
    unix_socket_directories: /tmp

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
