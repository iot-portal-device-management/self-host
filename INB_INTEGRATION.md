<h1 align="center">
  In-Band Manageability
</h1>

IoT Portal Device Management requires [Intel® In-Band Manageability][intel-inb-manageability] (INB) to be installed on 
the IoT devices for remote over-the-air (OTA) updates to function.

[intel-inb-manageability]: https://github.com/intel/intel-inb-manageability

## 📋 Requirements

- [Docker](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- IoT Portal Device Management

## ⚒️ Integrating IoT Portal Device Management adapter

Below are the steps to integrate IoT Portal Device Management adapter into Intel® In-Band Manageability. The following 
guide assumes that you already have the Intel® In-Band Manageability source code and is at the project root directory.

### INB Source Code Modification

Create the `iot_portal_device_management_adapter.py` file with the following contents in 
`inbm/cloudadapter-agent/cloudadapter/cloud/adapters/iot_portal_device_management_adapter.py` from the repository root 
of INB.
<details>
  <summary>iot_portal_device_management_adapter.py</summary>

```python
"""
Adapter for communication with the cloud agent on the device. It abstracts
creation of the cloud connection, termination, creating commands etc.

Connects to IoT Portal Device Management via the General Cloud MQTT client

Copyright (C) 2017-2022 Intel Corporation
SPDX-License-Identifier: Apache-2.0
"""

from ...exceptions import AdapterConfigureError, ClientBuildError
from ...constants import (IOT_PORTAL_DEVICE_MANAGEMENT_ENDPOINT,
                          IOT_PORTAL_DEVICE_MANAGEMENT_MQTT_PORT,
                          IOT_PORTAL_DEVICE_MANAGEMENT_CACERT)
from ..cloud_builders import build_client_with_config
from ..client.cloud_client import CloudClient
from .adapter import Adapter
from base64 import b64encode, b64decode
from hashlib import sha256
from future.moves.urllib.request import quote
from hmac import HMAC
from time import time, sleep
from typing import Optional, Any, Dict, Callable, Tuple
import requests
import json
import logging

logger = logging.getLogger(__name__)


class IotPortalDeviceManagementAdapter(Adapter):
    def __init__(self, configs: dict) -> None:
        super().__init__(configs)

    def configure(self, configs: dict) -> CloudClient:
        """Configure the IoT Portal Device Management cloud adapter

        @param configs: schema conforming JSON config data
        @exception AdapterConfigureError: If configuration fails
        """
        user_id = configs.get("user_id")
        if not user_id:
            raise AdapterConfigureError("Missing IoT Portal Device Management account user ID")

        device_connection_key = configs.get("device_connection_key")
        if not device_connection_key:
            raise AdapterConfigureError("Missing IoT Portal Device Management Device Connection Key")

        device_id = configs.get("device_id", None)

        hostname, device_id, device_mqtt_password = self._retrieve_mqtt_credentials(user_id,
                                                                                    device_connection_key,
                                                                                    device_id)

        event_pub = f"devices/{device_id}/messages/events/"
        config = {
            "mqtt": {
                "username": device_id,
                "password": device_mqtt_password,
                "hostname": hostname,
                "client_id": device_id,
                "port": IOT_PORTAL_DEVICE_MANAGEMENT_MQTT_PORT
            },
            "tls": {
                "version": "TLSv1.2",
                "certificates": str(IOT_PORTAL_DEVICE_MANAGEMENT_CACERT)
            },
            "event": {
                "pub": event_pub,
                "format": "{\"eventGeneric\": \"{value}\"}"
            },
            "telemetry": {
                "pub": event_pub,
                "format": "{\"{key}\": \"{value}\"}"
            },
            "attribute": {
                "pub": "devices/{}/properties/reported/".format(device_id),
                "format": "{\"{key}\": \"{value}\"}"
            },
            "method": {
                "pub": "iotportal/{}/methods/res/{}".format(device_id, "{request_id}"),
                "format": "",
                "sub": "iotportal/{}/methods/POST/#".format(device_id),
                "parse": {
                    "single": {
                        "request_id": {
                            "regex": r"iotportal\/{}\/methods\/POST\/(\w+)\/([\w=?$-]+)".format(device_id),
                            "group": 2
                        },
                        "method": {
                            "regex": r"iotportal\/{}\/methods\/POST\/(\w+)\/([\w=?$-]+)".format(device_id),
                            "group": 1
                        },
                        "args": {
                            "path": ""
                        }
                    }
                }
            }
        }

        try:
            return build_client_with_config(config)
        except ClientBuildError as e:
            raise AdapterConfigureError(str(e))

    def _retrieve_mqtt_credentials(self, user_id, device_connection_key, existing_device_id):
        """Retrieve the IoT Portal Device Management credentials associated to the device
        @param user_id: (str) The account user id
        @param device_connection_key: (str) The device connection key
        @param existing_device_id: (str) The existing device id
        @return: (tuple) The IoT Portal Device Management MQTT hostname, device id and device MQTT password
        """

        # Set up the initial HTTP request
        endpoint = "{}/api/devices/register".format(IOT_PORTAL_DEVICE_MANAGEMENT_ENDPOINT)
        headers = {
            "Accept": "application/json",
            "Content-Type": "application/json; charset=utf-8",
            "Connection": "keep-alive",
            "UserAgent": "prov_device_client/1.0",
            "Authorization": "Bearer {}".format(device_connection_key),
        }

        if existing_device_id:
            payload = {'userId': user_id, 'deviceId': existing_device_id}
            # Place a registration request for the device
            result = requests.post(endpoint, headers=headers, json=payload, verify=IOT_PORTAL_DEVICE_MANAGEMENT_CACERT)
        else:
            payload = {'userId': user_id}

            # Place a registration request for the device
            result = requests.post(endpoint, headers=headers, json=payload, verify=IOT_PORTAL_DEVICE_MANAGEMENT_CACERT)
        data = result.json()

        # Get the device's assigned hub
        if result.ok:
            mqtt_endpoint = data.get("result").get("mqttEndpoint")

            device = data.get("result").get("device")
            device_id = device.get("id")
            device_mqtt_password = device.get("mqttPassword")
            return [mqtt_endpoint, device_id, device_mqtt_password]
        else:
            error = "Ran into an error retrieving hostname: {} {}".format(
                result.status_code, result.text)
            raise AdapterConfigureError(error)

    def bind_callback(self, name: str, callback: Callable) -> None:
        """Bind a callback to be triggered by a method called on the cloud
        The callback has the signature: (**kwargs) -> (str)
            (**kwargs): Keys/types are documented per action function
            (str): The success status and an accompanying message

        @param name:     callback method name
        @param callback: callback to trigger
        """
        self._client.bind_callback(name, callback)
```
</details>
<br />

Add the following contents to the end of `constants.py` file in `inbm/cloudadapter-agent/cloudadapter/constants.py` from 
the repository root of INB. These are the necessary constants for the adapter.
<details>
  <summary>constants.py</summary>

```python
# ========== IoT Portal Device Management configuration constants


# Endpoint for device provisioning
IOT_PORTAL_DEVICE_MANAGEMENT_ENDPOINT = "https://<your-portal-hostname>"

# The port to which the IoT Portal Device Management MQTTClient should connect
IOT_PORTAL_DEVICE_MANAGEMENT_MQTT_PORT = 8883

IOT_PORTAL_DEVICE_MANAGEMENT_CACERT = INTEL_MANAGEABILITY_ETC_PATH_PREFIX / \
                                      'public' / 'cloudadapter-agent' / 'rootCA.crt'
```
</details>
<br />

Modify the `main.go` file in `inbm/fpm/inb-provision-cloud/main.go` from the repository root of INB according to the 
following instructions.
<details>
  <summary>main.go</summary>

Add the following additional functions into the `main.go` file:
```go
func configureIotPortalDeviceManagement() string {
	println("\nConfiguring to use IoT Portal Device Management...")

	userId := promptString("Please enter your account user ID:")
	deviceConnectionKey := promptString("Please enter your Device Connection Key:")
	deviceId := promptString("Please enter your Device ID (optional):")

	return makeIotPortalDeviceManagementJson(userId, deviceConnectionKey, deviceId)
}

func makeIotPortalDeviceManagementJson(userId string, deviceConnectionKey string, deviceId string) string {
	return `{ "cloud": "iotportaldevicemanagement", "config": { "user_id": "` + userId +
	`", "device_connection_key": "` + deviceConnectionKey +
	`", "device_id": "` + deviceId + `" } }`
}
```

Modify the `setUpCloudCredentialDirectory` function in the `main.go` file to add an additional `selection` and `case` 
for `IoT Portal Device Management` selection:
```go
selection := promptSelect("Please choose a cloud service to use.",
    []string{"Telit Device Cloud", "Azure IoT Central", "ThingsBoard", "IoT Portal Device Management", "Custom"})

case "IoT Portal Device Management":
    cloudConfig = configureIotPortalDeviceManagement()
```
</details>
<br />

Modify the `adapter_factory.py` file in `inbm/cloudadapter-agent/cloudadapter/cloud/adapter_factory.py` from the 
repository root of INB according to the following instructions.
<details>
  <summary>adapter_factory.py</summary>

Import the `IotPortalAdapter` module and modify the `get_adapter` function in the `adapter_factory.py` file to add a case for IoT Portal adapter:
```python
from .adapters.iot_portal_device_management_adapter import IotPortalDeviceManagementAdapter

    elif cloud == "iotportaldevicemanagement":
        return IotPortalDeviceManagementAdapter(config)
```
</details>

### Adding Self-Signed CA Certificate to Build
If you are using self-signed CA certificate, follow the step below to add the certificate to the build.

Copy the `rootCA.crt` file from `./iot-portal-device-management-data/certificates/rootCA.crt` of your IoT Portal Device 
Management installation to `inbm/cloudadapter-agent/fpm-template/etc/intel-manageability/public/cloudadapter-agent`.

### Building
Navigate to the root directory of the INB source code and build INB using the `./build.sh` build script.
```shell
./build.sh
```

### Installing and Provisioning
Proceed to follow the [Intel® In-Band Manageability Ubuntu Installation Guide](https://github.com/intel/intel-inb-manageability/blob/develop/docs/In-Band%20Manageability%20Installation%20Guide%20Ubuntu.md)
for installing and provisioning.
