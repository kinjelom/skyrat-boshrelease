#!/bin/bash

set -e # exit immediately if a simple command exits with a non-zero status
set -u # report the usage of uninitialized variables

export LANG=en_US.UTF-8
export JOB_NAME=firehose_to_syslog
export TMP_DIR=/var/vcap/sys/tmp/$JOB_NAME
export JOB_DIR=/var/vcap/jobs/$JOB_NAME
export DB_DIR=/var/vcap/store/$JOB_NAME/data

wait_for_service_on_port() {
  n=0
  until [ $n -ge 24 ]
  do
    nc -4 -z -v $1 $2 2>&1 && break
    n=$[$n+1]
    echo "Waiting for $1:$2 to accept connections ($n of 24)..."
    sleep 5
  done

  if [ "$n" -ge "24" ]; then
     echo "ERROR:  Cannot connect to $1:$2. Exiting..."
     exit 1
  fi
}

<%
  syslog_port = p('firehose_to_syslog.syslog.port')
  api_endpoint = p('firehose_to_syslog.cloudfoundry.api_endpoint')
%>

echo "Waiting 2m for syslog ingestor to accept connections..."
wait_for_service_on_port <%= p("firehose_to_syslog.syslog.host") %> <%= syslog_port %>

/var/vcap/packages/firehose_to_syslog/bin/firehose_to_syslog \
    --api-endpoint=<%= api_endpoint %> \
    <% if_p("firehose_to_syslog.cloudfoundry.doppler_endpoint") do |endpoint| %>--doppler-endpoint=<%= endpoint %><% end %> \
    <% if_p("firehose_to_syslog.syslog.cert_pem") do %>--cert-pem-syslog=${JOB_DIR}/config/cert.pem<% end %> \
    <% if_p("firehose_to_syslog.cloudfoundry.skip_ssl_validation") do %>--skip-ssl-validation <% end %> \
    --client-id=<%= p("firehose_to_syslog.cloudfoundry.firehose_client_id") %> \
    --client-secret=<%= p("firehose_to_syslog.cloudfoundry.firehose_client_secret") %> \
    --syslog-protocol=<%= p("firehose_to_syslog.syslog.protocol") %>\
    --syslog-server=<%= p("firehose_to_syslog.syslog.host") %>:<%= syslog_port %>\
    <% if_p("firehose_to_syslog.syslog.skip_ssl_validation") do %>--skip-ssl-validation-syslog <% end %> \
    --events=<%= p('firehose_to_syslog.cloudfoundry.firehose_events').join(',') %> \
    <% if_p("firehose_to_syslog.cloudfoundry.orgs") do |orgs| %> --orgs="<%= orgs.join(',') %>" <% end %> \
    <% if_p("firehose_to_syslog.cloudfoundry.app_name_suffixes_to_strip") do |suffixes| %> --strip-app-name-suffixes="<%= suffixes.join(',') %>" <% end %> \
    <% if_p("firehose_to_syslog.cloudfoundry.extra_fields") do |fields| %> --extra-fields="<%= fields.map { |key, value| "#{key}:#{value}" }.join(',') %>" <% end %> \
    <% if_p("firehose_to_syslog.cloudfoundry.ignore_missing_apps") do %>--ignore-missing-apps  <% end %> \
    <% if_p("firehose_to_syslog.enable_stats_server") do %>--enable-stats-server  <% end %> \
    --subscription-id=<%= p("firehose_to_syslog.cloudfoundry.firehose_subscription_id") %> \
    --boltdb-path=$DB_DIR/firehose_to_syslog.cache.db \
    --logs-buffer-size=<%= p("firehose_to_syslog.cloudfoundry.logs_buffer_size") %> \
    --min-retry-delay=<%= p("firehose_to_syslog.cloudfoundry.min_retry_delay") %> \
    --log-formatter-type=<%= p("firehose_to_syslog.cloudfoundry.log_formatter_type") %> \
    --max-retry-delay=<%= p("firehose_to_syslog.cloudfoundry.max_retry_delay") %> \
    --max-retry-count=<%= p("firehose_to_syslog.cloudfoundry.max_retry_count") %> \
    --cc-rps=<%= p("firehose_to_syslog.cloudfoundry.cc_polling_request") %> \
    --cc-pull-time=<%= p("firehose_to_syslog.cloudfoundry.firehose_cc_pull_interval") %> \
    <% if_p("firehose_to_syslog.debug") do %>--debug \<% end%>
