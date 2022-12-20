#!/usr/bin/env bash
set -e

# Setup

if command -v docker-compose &>/dev/null; then
  docker_compose_command='docker-compose'
else
  docker_compose_command='docker compose'
fi

CYAN='\033[0;36m'
RED='\033[1;31m'
NC='\033[0m' # No Color

OUTPUT_DIR=".."
if [ $# -gt 1 ]; then
  OUTPUT_DIR=$2
fi

SOURCE_URL="https://github.com/intel-innersource/applications.manageability.iot-portal-device-management."
if [ $# -gt 2 ]; then
  SOURCE_URL=$3
fi

DEPLOYMENT_VERSION="main"
if [ $# -gt 3 ]; then
  DEPLOYMENT_VERSION=$4
fi

API_VERSION="main"
if [ $# -gt 4 ]; then
  API_VERSION=$5
fi

NGINX_VERSION="main"
if [ $# -gt 5 ]; then
  NGINX_VERSION=$6
fi

POSTGRES_VERSION="main"
if [ $# -gt 6 ]; then
  POSTGRES_VERSION=$7
fi

REDIS_VERSION="main"
if [ $# -gt 7 ]; then
  REDIS_VERSION=$8
fi

VERNEMQ_VERSION="master"
if [ $# -gt 8 ]; then
  VERNEMQ_VERSION=$9
fi

WEB_VERSION="main"
if [ $# -gt 9 ]; then
  WEB_VERSION=${10}
fi

CERTIFICATE_OUTPUT_DIR="$OUTPUT_DIR"/certificates
COMPOSE_FILE_PARAMETERS="-f compose/docker-compose.yml -f compose/docker-compose.production.yml"

# Functions

function install() {
  if [ "$1" == "pull" ]; then
    cloneRepos
  fi

  checkRequiredCredentialsNotEmpty

  echo -e -n "${CYAN}(!)${NC} Enter the domain name for your IoT Portal Device Management instance (ex. iotportaldevicemanagement.com): "
  read DOMAIN
  echo ""

  if [ "$DOMAIN" == "" ]; then
    # Ensure net-tools exists before proceeding
    if ! command -v ip &>/dev/null; then
      echo -e "${CYAN}(!)${NC} Installing dependencies..."
      sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq net-tools >/dev/null
    fi

    # Determine default host machine IP address and assign as domain
    DOMAIN=$(ip route get 1 | awk '{print $7}' | head -1)
  fi

  echo -e -n "${CYAN}(!)${NC} Generate and replace APP_KEY? (y/n): "
  read GENERATE_APP_KEY

  # Build the API image required for key generation
  buildApiImage
  generateCredentials "$DOMAIN" "$GENERATE_APP_KEY"

  # Resource the .env.production file
  readEnvs

  # Create named volumes and label them first
  createNamedVolumes
  generateCerts "$DOMAIN"

  # Build other required images
  buildNginxImage
  buildPostgresImage
  buildRedisImage
  buildVernemqImage
  buildWebImage
}

function restart() {
  dockerComposeDown
  dockerComposeUp
}

function dockerComposeUp() {
  cd "$OUTPUT_DIR"/deployment

  $docker_compose_command "$COMPOSE_FILE_PARAMETERS" -p iotportaldevicemanagement --env-file .env.production up -d
}

function dockerComposeDown() {
  cd "$OUTPUT_DIR"/deployment

  if [ "$($docker_compose_command "$COMPOSE_FILE_PARAMETERS" \
    -p iotportaldevicemanagement \
    --env-file .env.production ps | wc -l)" -gt 1 ]; then
    echo -e "${CYAN}(!)${NC} Shutting down existing deployment..."
    $docker_compose_command "$COMPOSE_FILE_PARAMETERS" -p iotportaldevicemanagement --env-file .env.production down
  fi
}

function rebuild() {
  dockerComposeDown
  dockerImagePrune
  install
}

function migrateDb() {
  docker exec -it iotportaldevicemanagement-api php artisan migrate --force
}

function seedDb() {
  docker exec -it iotportaldevicemanagement-api php artisan db:seed --force
}

function seedDbSample() {
  docker exec -it iotportaldevicemanagement-api php artisan db:seed --class=SampleDatabaseSeeder --force
}

function clearDb() {
  echo -e -n "${RED}(!) This will clear the entire database records. Continue? (Y/N): ${NC}"
  read ANSWER
  echo ""

  if [ "$ANSWER" == "y" ] || [ "$ANSWER" == "Y" ]; then
    docker exec -it iotportaldevicemanagement-api php artisan migrate:fresh --force
  fi
}

function uninstall() {
  echo -e -n "${RED}WARNING: ALL DATA WILL BE REMOVED, INCLUDING THE FOLDER $OUTPUT_DIR: Are you sure you want to "$(
  )"uninstall IoT Portal Device Management? (y/n): ${NC}"
  read UNINSTALL_ACTION

  if [ "$UNINSTALL_ACTION" == "y" ]; then
    echo -e "${CYAN}(!)${NC} Uninstalling IoT Portal Device Management..."
    dockerComposeDown

    echo -e "${CYAN}(!)${NC} Removing $OUTPUT_DIR"
    rm -rf "$OUTPUT_DIR"

    echo -e "${CYAN}(!)${NC} Removing IoT Portal Device Management container images..."
    dockerImagePrune

    echo -e -n "${RED}(!) Would you like to prune all local IoT Portal Device Management docker volumes? (y/n): ${NC}"
    read PURNE_ACTION

    if [ "$PURNE_ACTION" == "y" ]; then
      docker volume prune --force --filter="label=com.iotportaldevicemanagement.product=iotportaldevicemanagement"
      echo -e "${CYAN}IoT Portal Device Management uninstall completed! ${NC}"
    fi
  else
    echo -e "${CYAN}(!) IoT Portal Device Management uninstall canceled. ${NC}"
    exit 1
  fi
}

function checkRequiredCredentialsNotEmpty() {
  readEnvs

  if [ "$APP_KEY" == "" ] ||
    [ "$DB_PASSWORD" == "" ] ||
    [ "$REDIS_PASSWORD" == "" ] ||
    [ "$MAIL_USERNAME" == "" ] ||
    [ "$MAIL_PASSWORD" == "" ] ||
    [ "$MQTT_AUTH_PASSWORD" == "" ]; then
    echo -e "${CYAN}(!)${NC} Please provide the required credentials e.g., APP_KEY, DB_PASSWORD, REDIS_PASSWORD, "$(
    )"MAIL_USERNAME, MAIL_PASSWORD, MQTT_AUTH_PASSWORD in $OUTPUT_DIR/deployment/.env.production file"
    exit 1
  fi
}

function cloneRepos() {
  if [ ! -d "$OUTPUT_DIR/api" ]; then
    git clone --depth 1 --branch "$API_VERSION" "$SOURCE_URL"api "$OUTPUT_DIR"/api
  fi

  if [ ! -d "$OUTPUT_DIR/nginx" ]; then
    git clone --depth 1 --branch "$NGINX_VERSION" "$SOURCE_URL"nginx "$OUTPUT_DIR"/nginx
  fi

  if [ ! -d "$OUTPUT_DIR/postgres" ]; then
    git clone --depth 1 --branch "$POSTGRES_VERSION" "$SOURCE_URL"postgres "$OUTPUT_DIR"/postgres
  fi

  if [ ! -d "$OUTPUT_DIR/redis" ]; then
    git clone --depth 1 --branch "$REDIS_VERSION" "$SOURCE_URL"redis "$OUTPUT_DIR"/redis
  fi

  if [ ! -d "$OUTPUT_DIR/docker-vernemq" ]; then
    git clone --depth 1 --branch "$VERNEMQ_VERSION" "$SOURCE_URL"docker-vernemq "$OUTPUT_DIR"/docker-vernemq
  fi

  if [ ! -d "$OUTPUT_DIR/web" ]; then
    git clone --depth 1 --branch "$WEB_VERSION" "$SOURCE_URL"web "$OUTPUT_DIR"/web
  fi

  if [ ! -d "$OUTPUT_DIR/deployment" ]; then
    git clone --depth 1 --branch "$DEPLOYMENT_VERSION" "$SOURCE_URL"deployment "$OUTPUT_DIR"/deployment
  fi
}

function generateCredentials() {
  DOMAIN=$1
  GENERATE_APP_KEY=$2

  cd "$OUTPUT_DIR"/deployment

  if [ "$GENERATE_APP_KEY" == "y" ]; then
    echo -e "${CYAN}(!)${NC} Generating APP_KEY..."
    APP_KEY=$(docker run --rm --entrypoint php iotportaldevicemanagement-api artisan key:generate --show)
    sed -i "s~APP_KEY=.*~APP_KEY=$APP_KEY~g" .env.production
  fi

  sed -i "s~APP_HOST=.*~APP_HOST=$DOMAIN~g" .env.production
}

function readEnvs() {
  cd "$OUTPUT_DIR"/deployment

  # Source the .env file
  . ./.env.production
}

function createNamedVolumes() {
  createNamedVolume "iotportaldevicemanagement_certificates"
  createNamedVolume "iotportaldevicemanagement_nginx-certificates"
  createNamedVolume "iotportaldevicemanagement_postgres-certificates"
  createNamedVolume "iotportaldevicemanagement_redis-certificates"
  createNamedVolume "iotportaldevicemanagement_vernemq-certificates"
  createNamedVolume "iotportaldevicemanagement_redis-acl"
}

function generateCerts() {
  DOMAIN=$1

  cd "$OUTPUT_DIR"/deployment

  docker build -f build/Dockerfile.production -t iotportaldevicemanagement-builder --build-arg HOSTNAME="$DOMAIN" .

  docker run -d --name=iotportaldevicemanagement-builder \
    -v iotportaldevicemanagement_certificates:/certificates \
    -v iotportaldevicemanagement_nginx-certificates:/nginx-certificates \
    -v iotportaldevicemanagement_postgres-certificates:/postgres-certificates \
    -v iotportaldevicemanagement_redis-certificates:/redis-certificates \
    -v iotportaldevicemanagement_vernemq-certificates:/vernemq-certificates \
    iotportaldevicemanagement-builder

  # Copy the certificates and keys out for backup
  createCertificatesDir
  docker cp iotportaldevicemanagement-builder:/certificates/* "$CERTIFICATE_OUTPUT_DIR"
  docker cp iotportaldevicemanagement-builder:/nginx-certificates/* "$CERTIFICATE_OUTPUT_DIR"/nginx-certificates
  docker cp iotportaldevicemanagement-builder:/postgres-certificates/* "$CERTIFICATE_OUTPUT_DIR"/postgres-certificates
  docker cp iotportaldevicemanagement-builder:/redis-certificates/* "$CERTIFICATE_OUTPUT_DIR"/redis-certificates
  docker cp iotportaldevicemanagement-builder:/vernemq-certificates/* "$CERTIFICATE_OUTPUT_DIR"/vernemq-certificates

  docker container stop iotportaldevicemanagement-builder
  docker container rm iotportaldevicemanagement-builder
}

function buildApiImage() {
  cd "$OUTPUT_DIR"/api

  docker build -f dockerfiles/build/Dockerfile.production -t api-builder .

  docker build -f dockerfiles/Dockerfile.production -t iotportaldevicemanagement-api .
}

function buildNginxImage() {
  cd "$OUTPUT_DIR"/nginx

  docker build -f Dockerfile.production -t iotportaldevicemanagement-nginx .
}

function buildPostgresImage() {
  cd "$OUTPUT_DIR"/postgres

  docker build -f Dockerfile.production -t iotportaldevicemanagement-postgres .
}

function buildRedisImage() {
  cd "$OUTPUT_DIR"/redis

  docker build -f build/Dockerfile.production -t redis-builder \
    --build-arg REDIS_USERNAME="$DOCKER_REDIS_USERNAME" \
    --build-arg REDIS_PASSWORD="$DOCKER_REDIS_PASSWORD" .

  # Create acl named volume for redis
  docker run -d --name=redis-builder -v iotportaldevicemanagement_redis-acl:/etc/redis/acl redis-builder

  docker container stop redis-builder
  docker container rm redis-builder

  docker build -f Dockerfile.production -t iotportaldevicemanagement-redis .
}

function buildVernemqImage() {
  cd "$OUTPUT_DIR"/docker-vernemq

  docker build -f Dockerfile.alpine -t iotportaldevicemanagement-vernemq .
}

function buildWebImage() {
  cd "$OUTPUT_DIR"/web

  docker build -f dockerfiles/Dockerfile.production -t iotportaldevicemanagement-web .
}

function createNamedVolume() {
  echo "Creating named volume $1"
  docker volume create --driver local \
    --label "com.iotportaldevicemanagement.product=iotportaldevicemanagement" \
    "$1"
}

function dockerImagePrune() {
  docker image prune --all --force --filter="label=com.iotportaldevicemanagement.product=iotportaldevicemanagement"
}

function createCertificatesDir() {
  createDir "$CERTIFICATE_OUTPUT_DIR/nginx-certificates"
  createDir "$CERTIFICATE_OUTPUT_DIR/postgres-certificates"
  createDir "$CERTIFICATE_OUTPUT_DIR/redis-certificates"
  createDir "$CERTIFICATE_OUTPUT_DIR/vernemq-certificates"
}

function createDir() {
  if [ ! -d "$1" ]; then
    echo "Creating directory $1"
    mkdir -p "$1"
  fi
}

# Commands

case $1 in
"install")
  install pull
  ;;
"offline-install")
  install noPull
  ;;
"start" | "restart")
  restart
  ;;
"stop")
  dockerComposeDown
  ;;
"rebuild")
  rebuild
  ;;
"migrate-db")
  migrateDb
  ;;
"seed-db")
  seedDb
  ;;
"seed-db-sample")
  seedDbSample
  ;;
"clear-db")
  clearDb
  ;;
"uninstall")
  uninstall
  ;;
esac
