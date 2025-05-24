#!/bin/bash

set -eu

source ./src/meta-info/blobs-versions.env
source ./rel.env

mkdir -p "$TMP_DIR"

function down_add_blob {
  BLOBS_GROUP=$1
  FILE=$2
  URL=$3
  if [ ! -f "blobs/${BLOBS_GROUP}/${FILE}" ];then
    echo "Downloads resource from the Internet ($URL -> $TMP_DIR/$FILE)"
    curl -L "$URL" --output "$TMP_DIR/$FILE"
    echo "Adds blob ($TMP_DIR/$FILE -> $BLOBS_GROUP/$FILE), starts tracking blob in config/blobs.yml for inclusion in packages"
    bosh add-blob "$TMP_DIR/$FILE" "$BLOBS_GROUP/$FILE"
  fi
}

down_add_blob "blackbox_exporter" "blackbox_exporter-${BLACKBOX_EXPORTER_VERSION}.linux-amd64.tar.gz" "$BLACKBOX_EXPORTER_URL"
down_add_blob "bosh_exporter" "bosh_exporter_${BOSH_EXPORTER_VERSION}.linux-amd64.tar.gz" "$BOSH_EXPORTER_URL"
down_add_blob "boshi_exporter" "boshi_exporter_${BOSHI_EXPORTER_VERSION}.linux-amd64.tar.gz" "$BOSHI_EXPORTER_URL"
down_add_blob "cf_exporter" "cf_exporter_${CF_EXPORTER_VERSION}.linux-amd64.tar.gz" "$CF_EXPORTER_URL"
down_add_blob "firehose_exporter" "firehose_exporter_${FIREHOSE_EXPORTER_VERSION}.linux-amd64.tar.gz" "$FIREHOSE_EXPORTER_URL"
down_add_blob "firehose_to_syslog" "firehose_to_syslog_${FIREHOSE_TO_SYSLOG_VERSION}" "$FIREHOSE_TO_SYSLOG_URL"
down_add_blob "pushgateway" "pushgateway_${PUSHGATEWAY_VERSION}.linux-amd64.tar.gz" "$PUSHGATEWAY_URL"
down_add_blob "watchdog_exporter" "watchdog_exporter_${WATCHDOG_EXPORTER_VERSION}.linux-amd64.tar.gz" "$WATCHDOG_EXPORTER_URL"

echo "Download blobs into blobs/ based on config/blobs.yml"
bosh sync-blobs

echo "Upload previously added blobs that were not yet uploaded to the blobstore. Updates config/blobs.yml with returned blobstore IDs."
bosh upload-blobs
