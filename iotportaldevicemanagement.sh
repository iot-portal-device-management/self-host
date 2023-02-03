#!/usr/bin/env bash
#
# Copyright (C) 2021-2023 Intel Corporation
# SPDX-License-Identifier: MIT
#

set -e

cat <<"EOF"
  _____   _______   _____           _        _   _____             _            __  __                                                   _
 |_   _| |__   __| |  __ \         | |      | | |  __ \           (_)          |  \/  |                                                 | |
   | |  ___ | |    | |__) |__  _ __| |_ __ _| | | |  | | _____   ___  ___ ___  | \  / | __ _ _ __   __ _  __ _  ___ _ __ ___   ___ _ __ | |_
   | | / _ \| |    |  ___/ _ \| '__| __/ _` | | | |  | |/ _ \ \ / / |/ __/ _ \ | |\/| |/ _` | '_ \ / _` |/ _` |/ _ \ '_ ` _ \ / _ \ '_ \| __|
  _| || (_) | |    | |  | (_) | |  | || (_| | | | |__| |  __/\ V /| | (_|  __/ | |  | | (_| | | | | (_| | (_| |  __/ | | | | |  __/ | | | |_
 |_____\___/|_|    |_|   \___/|_|   \__\__,_|_| |_____/ \___| \_/ |_|\___\___| |_|  |_|\__,_|_| |_|\__,_|\__, |\___|_| |_| |_|\___|_| |_|\__|
                                                                                                          __/ |
                                                                                                         |___/

EOF

cat <<EOF
IoT Portal Device Management
Copyright 2021-$(date +'%Y'), Intel Corporation

===================================================

EOF

# Setup

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$DIR/iot-portal-device-management-data"

if [ $# -eq 2 ]; then
  OUTPUT_DIR=$2
fi

if command -v docker-compose &>/dev/null; then
  docker_compose_command='docker-compose'
else
  docker_compose_command='docker compose'
fi

SOURCE_URL="https://github.com/iot-portal-device-management/"
CORE_VERSION="v2.0.0"
DEPLOYMENT_VERSION="v2.0.0"
API_VERSION="v2.0.0"
NGINX_VERSION="v1.23.2-alpine"
POSTGRES_VERSION="v15.0-alpine3.16"
REDIS_VERSION="v7.0.5-alpine3.16"
VERNEMQ_VERSION="1.12.3"
WEB_VERSION="v2.0.0"

# Echo version

echo "iotportaldevicemanagement.sh version $CORE_VERSION"
docker --version
if [[ "$docker_compose_command" == "docker-compose" ]]; then
  $docker_compose_command --version
else
  $docker_compose_command version
fi

echo ""

# Functions

function checkOutputDirExists() {
  if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Cannot find a IoT Portal Device Management installation at $OUTPUT_DIR."
    exit 1
  fi
}

function checkOutputDirNotExists() {
  if [ -d "$OUTPUT_DIR" ]; then
    echo "Looks like IoT Portal Device Management is already installed at $OUTPUT_DIR."
    exit 1
  fi
}

function listCommands() {
  cat <<EOT
Available commands:

install
offline-install
start
restart
stop
rebuild
migrate-db
seed-db
seed-db-sample
clear-db
uninstall
help

EOT
}

# Commands

case $1 in
"install")
  checkOutputDirNotExists
  mkdir -p "$OUTPUT_DIR"
  "$DIR"/run.sh install "$OUTPUT_DIR" $SOURCE_URL $DEPLOYMENT_VERSION $API_VERSION $NGINX_VERSION $POSTGRES_VERSION \
                        $REDIS_VERSION $VERNEMQ_VERSION $WEB_VERSION
  ;;
"offline-install")
  checkOutputDirExists
  "$DIR"/run.sh offline-install "$OUTPUT_DIR" $SOURCE_URL $DEPLOYMENT_VERSION $API_VERSION $NGINX_VERSION \
                                $POSTGRES_VERSION $REDIS_VERSION $VERNEMQ_VERSION $WEB_VERSION
  ;;
"start" | "restart")
  checkOutputDirExists
  "$DIR"/run.sh restart "$OUTPUT_DIR"
  ;;
"stop")
  checkOutputDirExists
  "$DIR"/run.sh stop "$OUTPUT_DIR"
  ;;
"rebuild")
  checkOutputDirExists
  "$DIR"/run.sh rebuild "$OUTPUT_DIR" $SOURCE_URL $DEPLOYMENT_VERSION $API_VERSION $NGINX_VERSION $POSTGRES_VERSION \
                        $REDIS_VERSION $VERNEMQ_VERSION $WEB_VERSION
  ;;
"migrate-db")
  checkOutputDirExists
  "$DIR"/run.sh migrate-db
  ;;
"seed-db")
  checkOutputDirExists
  "$DIR"/run.sh seed-db
  ;;
"seed-db-sample")
  checkOutputDirExists
  "$DIR"/run.sh seed-db-sample
  ;;
"clear-db")
  checkOutputDirExists
  "$DIR"/run.sh clear-db
  ;;
"uninstall")
  checkOutputDirExists
  "$DIR"/run.sh uninstall "$OUTPUT_DIR"
  ;;
"help")
  listCommands
  ;;
*)
  echo "No command found."
  echo
  listCommands
  ;;
esac
