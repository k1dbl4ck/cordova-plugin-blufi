# Cordova BluFi Plugin

- This plugin implements the [Espressif BluFi API](https://docs.espressif.com/projects/esp-idf/en/latest/api-guides/blufi.html) for ESP32 based chipsets with Bluetooth.
- It provides a secure protocol to pass Wi-Fi configuration and credentials to the ESP32. Using this information ESP32 can then, for example, connect to an AP or establish a SoftAP.

## Supports
Android API 23+
iOS 10.2+

## Requirements
- A ESP32 board running BluFi compatible firmware
- Apache Cordova 8.1.2 (cordova-lib@8.1.1) or newer
- Android SDK (if developing for Android)
- XCode (if developing for iOS)

## Installation 

To install run the following in your Cordova project directory
```
cordova plugin add cordova-plugin-blufi
```

## Using

Once installed, the plugin will be available in Javascript on the following namespace:
```js
window.cordova.plugins.blufi
```

The following API calls are available on the above namespace:

| Method        | Description                                                                      |
| ------------- |:--------------------------------------------------------------------------------:| 
| search        | Initiates a search for BLE devices and returns an array containing devices found | 
| connect       | Connects to a BluFi compatible BLE device                                        | 
| disconnect    | Disconnects from currently connected device                                      |  
| negotiate     | Negotiates a secure connection with the connected BluFi device                   | 
| configure     | Configures the WiFi mode and associated credentials of the connected BluFi device| 
| send          | Send a string of custom data to the connected BluFi device                       | 
| version       | Returns the version as reported by the connected BluFi device                    | 
| status        | Returns the current status of the connected BluFi device                         | 


### Searching for devices

If you do not know the name or address of the device you want to connect to, you need to first initiate a search, which scans for all available BLE devices 
- The first parameter is a prefix to filter results on before passed back to you (default: "")
- The second parameter is the maximum duration in milliseconds to scan for (default: 5000)
```js
    let blufi = window.cordova.plugins.blufi;

    blufi.search(
    "name", 
     10000, 
    (success) => { 
        
    }, 
    (error) => {

    }); 

```

Response: 
  [
    {address: "5B:FD:EC:A7:DE:FC", type: 0}
    {address: "4A:72:BE:54:07:9B", type: 0}
    {name: "BLUFI_DEVICE", address: "24:0A:C4:97:12:BE", type: 2}
    {address: "56:1D:78:D3:49:D7", type: 0}
    {address: "71:B2:74:83:2C:F9", type: 0}
  ]

*** Note: Some BLE devices will broadcast their name and others won't. ***

### Connecting to a device

Once you know the name or address of the device you want to connect to, you can connect as follows: 
```js
    let blufi = window.cordova.plugins.blufi;

    blufi.connect(
    { 
      identifier:"24:0A:C4:97:12:BE"  // name or address as retrieved from search call
    }, 
    (success) => { 
        console.log(success); 
    }, 
    (error) => {
	    console.error(error); 
    }); 

```

You should recieve a response in your successCallback as follows: 
 ```js
   {
      connected: true, 
      address: "24:0A:C4:97:12:BE", 
      code: 0
   }

 ```

### Negotating security with connected device

Once connected, security can be negotatiated as follows:
```js
    let blufi = window.cordova.plugins.blufi;

    blufi.negotiate( 
    (success) => { ... }, 
    (error) => { ... }); 
```

### Configuring BluFi

Once connected, you can configure the device as follows
```js
    let blufi = window.cordova.plugins.blufi;

    //For station mode (replace ssid and password with valid credentials): 
    blufi.configure(
    { 
      mode:"station",
      ssid:"SSID_OF_WIFI_NETWORK", 
      password:"PASSWORD_OF_WIFI_NETWORK"
    }, 
    (success) => { 
        console.log(success); 
    }, 
    (error) => {
	    console.error(error); 
    }); 

    //For softAP mode (replace ssid and password with valid credentials): 
    blufi.configure(
    { 
      mode:"softap",
      ssid:"TEST-SSID",  // The WiFi SSID you would like the device to broadcast
      security: "wpa2-psk", // One of ['open', 'wpa-psk', 'wpa2-psk', 'wpa-wap2-psk']
      password:"abcd1234" // A WiFi password (if security mode is not set as "open") clients can use to connect
    }, 
    (success) => { 
        console.log(success); 
    }, 
    (error) => {
	    console.error(error); 
    }); 

    //For combined station/softAP mode (replace ssid and password with valid credentials): 
    blufi.configure(
    { 
      mode:"stasoftap",
      station: { 
        ssid:"SSID_OF_WIFI_NETWORK", 
        password:"PASSWORD_OF_WIFI_NETWORK"
      },
      softap: { 
        ssid:"TEST-SSID", 
        security: "wpa2-psk", 
        password:"abcd1234" 
      }
    }, 
    (success) => { 
        console.log(success); 
    }, 
    (error) => {
	    console.error(error); 
    }); 


```

### Getting device status

Once connected, you can request the current status of the device:
```js
    let blufi = window.cordova.plugins.blufi;

    blufi.status( 
    (success) => { ... }, 
    (error) => { ... }); 
```

### Getting device version

Once connected, you can request the current version of the device:
```js
    let blufi = window.cordova.plugins.blufi;

    blufi.version( 
    (success) => { ... }, 
    (error) => { ... }); 
```

### Sending custom data to the device

Once connected, you can send custom data to the device:
```js
    let blufi = window.cordova.plugins.blufi;

    blufi.send(
    "some string of data - possibly stringified JSON",  
    (success) => { ... }, 
    (error) => { ... }); 
```

### Disconnecting from currently connected device

Once you are done setting up the device, you can disconnect the Bluetooth connection
```js
    let blufi = window.cordova.plugins.blufi;

    blufi.disconnect( 
    (success) => { ... }, 
    (error) => { ... }); 
```




## References
[Espressif BluFi API](https://docs.espressif.com/projects/esp-idf/en/latest/api-guides/blufi.html)
[BluFi API for Android](https://github.com/EspressifApp/EspBlufiForAndroid)



## Development

### Building the Espressif BluFi libraries
```
cd apptools
gradle build
cp build/outputs/aar/apptools-release.aar **/cordova-plugin-blufi/libs/android
```



## More Info

For more information on setting up Cordova see [the documentation](http://cordova.apache.org/docs/en/latest/guide/cli/index.html)
For more info on plugins see the [Plugin Development Guide](http://cordova.apache.org/docs/en/latest/guide/hybrid/plugins/index.html)
