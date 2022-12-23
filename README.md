<h1 align="center">
  <a href="https://github.com/iot-portal-device-management/self-host">
    Self Host Repository
  </a>
</h1>

IoT Portal Device Management is a web application that interacts with Intel In-Band Manageability to provide remote 
over-the-air (OTA) updates to IoT devices. It supports Firmware OTA (FOTA), Software OTA (SOTA), Application OTA (AOTA) 
and Configuration OTA (COTA). 

- Supports FOTA, SOTA, AOTA and COTA features.
- Device categorization feature.
- Device grouping feature.
- Saved command feature.
- Mass OTA update feature.
- Robust Mass OTA background job processing.

## 📋 Requirements

- [Docker Engine 20.10](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Compose 1.29.2](https://docs.docker.com/compose/install/)

*These dependencies are free to use.*

## 🔧 Installation

You can install IoT Portal Device Management using Docker containers on Linux distributions. Use the provided Bash scripts to get started quickly.

### Linux

#### Installing Docker and Docker Compose

Install Docker Engine 20.10

```shell
curl -fsSL https://get.docker.com -o get-docker.sh
sudo VERSION=20.10 sh get-docker.sh
```

Optionally, manage Docker as a non-root user by following the instructions at 
[Manage Docker as a non-root user](https://docs.docker.com/engine/install/linux-postinstall/#manage-docker-as-a-non-root-user).

```shell
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker
```

Install Docker Compose 2.14.2

```shell
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.14.2/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
```

#### Install IoT Portal Device Management

Clone the repository to your system:

```shell
git clone https://github.com/iot-portal-device-management/self-host
```

Navigate to the `self-host` directory and give it permission to execute:

```shell
cd self-host && chmod +x *.sh
```

Run the installation script. A `./iot-portal-device-management-data` directory will be created.

```shell
./iotportaldevicemanagement.sh install 
```

The default email delivery service used is [Mailtrap](https://mailtrap.io/). You are free to use other email
delivery services. Provide the required credentials e.g., `APP_KEY` (optional), `DB_PASSWORD`, `REDIS_PASSWORD`, 
`MAIL_USERNAME`, `MAIL_PASSWORD`, `MQTT_AUTH_PASSWORD` in `./iot-portal-device-management-data/deployment/.env.production` 
file and run:

```shell
./iotportaldevicemanagement.sh offline-install 
```

Finally, start IoT Portal Device Management services.

```shell
./iotportaldevicemanagement.sh start 
```

Migrate the database for the first run.

```shell
./iotportaldevicemanagement.sh migrate-db 
```

Seed the database.

```shell
./iotportaldevicemanagement.sh seed-db 
```

To seed the database with sample data, run the command below. A random generated user will be created with the password 
defaulted to `password`.

*ONLY TRY THIS ON DEVELOPMENT INSTANCE! THIS IS FOR YOU TO EXPERIMENT THE FEATURES WITHOUT ACTUALLY PROVISIONING A DEVICE.*

```shell
./iotportaldevicemanagement.sh seed-db-sample 
```

By default, the script uses values in the `.env.production` file for deployment. You should replace those default 
credentials, e.g. `APP_KEY`, `DB_PASSWORD`, `REDIS_PASSWORD`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MQTT_AUTH_PASSWORD` 
etc. with your own randomly generated password for production deployment.

## 📖 Script Commands Reference

Command | Description
---------------------- | ------------------------------------
`install` | Start the online installer.
`offline install` | Start the offline installer.
`start` | Start all services.
`restart`	| Restart all services (same as `start`).
`stop` | Stop all services.
`rebuild`	| Rebuild the images.
`migrate-db` | Update/initialize the database.
`seed-db` | Seed all required data for first run.
`seed-db-sample` | Seed the database with sample data. (Development use only)
`clear-db` | Clear the entire database. (Development use only)
`uninstall` | Uninstall IoT Portal Device Management
`help` | List all commands.

*Use these commands cautiously. Some commands are intended for development purpose only.*

## ⚒️ Intel® In-Band Manageability Integration

Read our [Integration Guide][inb-integration] to learn how to integrate the IoT Portal Device Management adapter into 
[Intel® In-Band Manageability][intel-inb-manageability].  

[inb-integration]: INB_INTEGRATION.md
[intel-inb-manageability]: https://github.com/intel/intel-inb-manageability

## 👏 Contributing

Thank you for considering contributing to the IoT Portal Device Management! PHPStorm is highly recommended if you are 
working on this project. Please commit any pull requests against the `main` branch.

## 📄 License

IoT Portal Device Management is open-sourced software licensed under the 
[GPL-2.0-or-later license](https://spdx.org/licenses/GPL-2.0-or-later.html).
