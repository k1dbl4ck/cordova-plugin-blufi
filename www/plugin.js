let DEFAULTS = {
    UUID_SERVICE: "0000ffff-0000-1000-8000-00805f9b34fb",
    UUID_WRITE_CHARACTERISTIC: "0000ff01-0000-1000-8000-00805f9b34fb",
    UUID_NOTIFICATION_CHARACTERISTIC: "0000ff02-0000-1000-8000-00805f9b34fb",
    TIMEOUT: 5000,
    PREFIX: "",
    MTU_LENGTH: 128
}


function getStationSetup(config, errorCallback) {

    if (!config.ssid || !config.password)
        return errorCallback("Invalid credentials: 'station' mode requires ssid and password to be set");
    let setup = {
        ssid: config.ssid,
        password: config.password
    }
    return setup;
}

function getSoftAPSetup(config, errorCallback) {


    if (!config.ssid) return errorCallback("Invalid ssid: 'softap' mode requires ssid to be set");
    if (!config.security || ['open', 'wpa-psk', 'wpa2-psk', 'wpa-wap2-psk'].indexOf(config.security) == -1)
        return errorCallback("Invalid security mode: requires one of ['open', 'wpa-psk', 'wpa2-psk', 'wpa-wap2-psk']");
    if (['wpa-psk', 'wpa2-psk', 'wpa-wap2-psk'].indexOf(config.security) > -1 && !config.password)
        return errorCallback("Invalid password: security modes in one of ['wpa-psk', 'wpa2-psk', 'wpa-wap2-psk'] requires a valid password");

    config.channel = config.channel || 1;
    config.maxConnections = config.maxConnections || 4;

    let setup = {
        ssid: config.ssid,
        security: config.security,
        password: config.password,
        channel: config.channel,
        maxConnections: config.maxConnections
    }
    return setup;
}


module.exports = {

    configure: (config, successCallback, errorCallback) => {

        if (!config.mode || ['station', 'softap', 'stasoftap'].indexOf(config.mode) == -1)
            return errorCallback("Invalid mode: requires one of ['station', 'softap', 'stasoftap']");

        let mode = config.mode;
        let setup = false;

        if (mode == "station") {
            setup = {
                mode: "station",
                config: getStationSetup(config, errorCallback)
            }
        } else if (mode == "softap") {
            setup = {
                mode: "softap",
                config: getSoftAPSetup(config, errorCallback)
            }
        } else if (mode == "stasoftap") {
            if (!config.station) return errorCallback("Invalid config: 'stasoftap' mode requires station configuration");
            if (!config.softap) return errorCallback("Invalid config: 'stasoftap' requires softap configuration");

            setup = {
                mode: "stasoftap",
                config: {
                    station: getStationSetup(config.station, errorCallback),
                    softap: getSoftAPSetup(config.softap, errorCallback)
                }
            }

        }

        if (setup) {
            cordova.exec(successCallback, errorCallback, "Gatt", "configure", [setup]);
        }

    },
    connect: (config, successCallback, errorCallback) => {

        if (!config.identifier || config.identifier == "") {
            errorCallback("Invalid indentifier");
        }

        config.uuid = config.uuid || {};
        config.uuid.service = config.uuid.service || DEFAULTS.UUID_SERVICE;
        config.uuid.write = config.uuid.write || DEFAULTS.UUID_WRITE_CHARACTERISTIC;
        config.uuid.notification = config.uuid.notification || DEFAULTS.UUID_NOTIFICATION_CHARACTERISTIC;
        config.mtu = config.mtu || DEFAULTS.MTU_LENGTH;

        cordova.exec(successCallback, errorCallback, "Gatt", "connect", [config]);
    },
    disconnect: (successCallback, errorCallback) => {
        cordova.exec(successCallback, errorCallback, "Gatt", "disconnect", []);
    },
    negotiate: (successCallback, errorCallback) => {
        cordova.exec(successCallback, errorCallback, "Gatt", "negotiate", []);
    },
    version: (successCallback, errorCallback) => {
        cordova.exec(successCallback, errorCallback, "Gatt", "version", []);
    },
    search: (prefix = "", timeout = 5000, successCallback, errorCallback) => {
        cordova.exec(successCallback, errorCallback, "Gatt", "search", [prefix, timeout]);
    },
    scan: (successCallback, errorCallback) => {
        cordova.exec(successCallback, errorCallback, "Gatt", "scan", []);
    },
    status: (successCallback, errorCallback) => {
        cordova.exec(successCallback, errorCallback, "Gatt", "status", []);
    },
    send: (data, successCallback, errorCallback) => {
        cordova.exec(successCallback, errorCallback, "Gatt", "send", [data]);
    }
};