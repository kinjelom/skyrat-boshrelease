#!/usr/bin/env bash

set -eu

RUN_DIR=/var/vcap/sys/run/pushgateway
LOG_DIR=/var/vcap/sys/log/pushgateway
TMP_DIR=/var/vcap/sys/tmp/pushgateway
STORE_DIR=/var/vcap/store/pushgateway
JOB_DIR=/var/vcap/jobs/pushgateway
mkdir -p ${RUN_DIR} ${LOG_DIR} ${TMP_DIR} ${STORE_DIR}

PIDFILE=${RUN_DIR}/pushgateway.pid

source /var/vcap/packages/pushgateway/common/utils.sh
exec 1>> ${LOG_DIR}/$(basename "$0").stdout.log
exec 2>> ${LOG_DIR}/$(basename "$0").stderr.log

export PATH=/var/vcap/packages/pushgateway/bin:${PATH}

case $1 in
  start)
    pid_guard ${PIDFILE} "pushgateway"
    echo $$ > ${PIDFILE}

    exec pushgateway \
      --web.listen-address=":<%= p('pushgateway.web.port') %>" \
      <% if_p('pushgateway.web.external_url') do |external_url| %> \
      --web.external-url="<%= external_url %>" \
      <% end %> \
      <% if_p('pushgateway.web.route_prefix') do |route_prefix| %> \
      --web.route-prefix="<%= route_prefix %>" \
      <% end %> \
      <% if_p('pushgateway.web.telemetry_path') do |telemetry_path| %> \
      --web.telemetry-path="<%= telemetry_path %>" \
      <% end %> \
      --web.config.file="${JOB_DIR}/config/web.yaml" \
      <% if_p('pushgateway.log_format') do |log_format| %> \
      --log.format="<%= log_format %>" \
      <% end %> \
      <% if_p('pushgateway.log_level') do |log_level| %> \
      --log.level="<%= log_level %>" \
      <% end %> \
      --persistence.file="${STORE_DIR}/pushgateway.metrics" \
      <% if_p('pushgateway.persistence_interval') do |persistence_interval| %> \
      --persistence.interval="<%= persistence_interval %>" \
      <% end %> \
      <% if p('pushgateway.push.disable_consistency_check') %>--push.disable-consistency-check <% end %> \
      <% if p('pushgateway.push.enable_utf8_names') %>--enable-utf8-names <% end %> \
      >>  ${LOG_DIR}/pushgateway.stdout.log \
      2>> ${LOG_DIR}/pushgateway.stderr.log
    ;;

  stop)
    kill_and_wait ${PIDFILE}
    ;;

  *)
    echo "Usage: $0 {start|stop}"
    exit 1
    ;;

esac
exit 0
