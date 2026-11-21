#!/bin/bash
<%
  require 'shellwords'
  q = lambda { |v| Shellwords.escape(v.to_s) }

  syslog_host = p('firehose_to_syslog.syslog.host')
  syslog_port = p('firehose_to_syslog.syslog.port')

  args = []
  args << "--api-endpoint=#{q.(p('firehose_to_syslog.cloudfoundry.api_endpoint'))}"
  if_p('firehose_to_syslog.cloudfoundry.doppler_endpoint') { |v| args << "--doppler-endpoint=#{q.(v)}" }
  args << "--client-id=#{q.(p('firehose_to_syslog.cloudfoundry.firehose_client_id'))}"
  args << "--client-secret=#{q.(p('firehose_to_syslog.cloudfoundry.firehose_client_secret'))}"
  args << "--subscription-id=#{q.(p('firehose_to_syslog.cloudfoundry.firehose_subscription_id'))}"
  args << "--syslog-protocol=#{q.(p('firehose_to_syslog.syslog.protocol'))}"
  args << "--syslog-server=#{q.("#{syslog_host}:#{syslog_port}")}"
  if_p('firehose_to_syslog.syslog.cert_pem') { args << '--cert-pem-syslog="${JOB_DIR}/config/cert.pem"' }
  args << "--events=#{q.(p('firehose_to_syslog.cloudfoundry.firehose_events').join(','))}"
  if_p('firehose_to_syslog.cloudfoundry.orgs') { |v| args << "--orgs=#{q.(Array(v).join(','))}" }
  if_p('firehose_to_syslog.cloudfoundry.app_name_suffixes_to_strip') { |v| args << "--strip-app-name-suffixes=#{q.(Array(v).join(','))}" }
  if_p('firehose_to_syslog.cloudfoundry.extra_fields') do |fields|
    args << "--extra-fields=#{q.(fields.map { |k, v| "#{k}:#{v}" }.join(','))}"
  end
  args << '--boltdb-path="${DB_DIR}/firehose_to_syslog.cache.db"'
  args << "--logs-buffer-size=#{q.(p('firehose_to_syslog.cloudfoundry.logs_buffer_size'))}"
  args << "--min-retry-delay=#{q.(p('firehose_to_syslog.cloudfoundry.min_retry_delay'))}"
  args << "--max-retry-delay=#{q.(p('firehose_to_syslog.cloudfoundry.max_retry_delay'))}"
  args << "--max-retry-count=#{q.(p('firehose_to_syslog.cloudfoundry.max_retry_count'))}"
  args << "--log-formatter-type=#{q.(p('firehose_to_syslog.cloudfoundry.log_formatter_type'))}"
  args << "--cc-rps=#{q.(p('firehose_to_syslog.cloudfoundry.cc_polling_request'))}"
  args << "--cc-pull-time=#{q.(p('firehose_to_syslog.cloudfoundry.firehose_cc_pull_interval'))}"

  # boolean switches: pass only when explicitly true (if_p would also fire on a `false` default)
  args << '--skip-ssl-validation'        if p('firehose_to_syslog.cloudfoundry.skip_ssl_validation')
  args << '--skip-ssl-validation-syslog' if p('firehose_to_syslog.syslog.skip_ssl_validation')
  args << '--ignore-missing-apps'        if p('firehose_to_syslog.cloudfoundry.ignore_missing_apps')
  args << '--enable-stats-server'        if p('firehose_to_syslog.enable_stats_server')
  args << '--debug'                      if p('firehose_to_syslog.debug')
-%>

set -e # exit immediately if a simple command exits with a non-zero status
set -u # report the usage of uninitialized variables

export LANG=en_US.UTF-8
export JOB_NAME=firehose_to_syslog
export TMP_DIR=/var/vcap/sys/tmp/$JOB_NAME
export JOB_DIR=/var/vcap/jobs/$JOB_NAME
export DB_DIR=/var/vcap/store/$JOB_NAME/data

wait_for_service_on_port() {
  local n=0
  until [ "$n" -ge 24 ]; do
    nc -4 -z -v "$1" "$2" 2>&1 && break
    n=$((n + 1))
    echo "Waiting for $1:$2 to accept connections ($n of 24)..."
    sleep 5
  done

  if [ "$n" -ge 24 ]; then
    echo "ERROR: Cannot connect to $1:$2. Exiting..."
    exit 1
  fi
}

echo "Waiting 2m for syslog ingestor to accept connections..."
wait_for_service_on_port <%= q.(syslog_host) %> <%= q.(syslog_port) %>

exec /var/vcap/packages/firehose_to_syslog/bin/firehose_to_syslog \
<%= args.map { |a| "  #{a}" }.join(" \\\n") %>
