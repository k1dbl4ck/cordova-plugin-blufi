package za.co.clearcell.blufi;

import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothProfile;
import android.content.Context;
import android.util.Log;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.List;
import java.util.Locale;
import java.util.UUID;

import blufi.espressif.BlufiCallback;
import blufi.espressif.BlufiClient;
import blufi.espressif.params.BlufiConfigureParams;
import blufi.espressif.response.BlufiScanResult;
import blufi.espressif.response.BlufiStatusResponse;
import blufi.espressif.response.BlufiVersionResponse;
import libs.espressif.app.SdkUtil;

public class Gatt extends CordovaPlugin implements SearchResultEvent {

    private BlufiClient mBlufiClient;
    private BluetoothGatt mGatt;
    private CallbackContext callbackContext;
    private volatile boolean mConnected;
    private Context context;

    private BluetoothDevice mDevice;

    private Response jsResponse;



    private UUID serviceUUID;
    private UUID writeUUID;
    private UUID notificationUUID;
    private int MTULength;
    private String identifier;

    private boolean connectOnSearchResult = false;


    private String TAG = "BLUFI";


    //------

    private CordovaInterface cordova;
    private Permissions permissions;
    private Search search;

    @Override
    public void initialize(CordovaInterface cordova, CordovaWebView webView) {
        super.initialize(cordova, webView);
        this.cordova = cordova;

        context = cordova.getActivity().getApplicationContext();
        search = new Search(cordova, this);
        permissions = new Permissions(cordova, this);
    }


    @Override
    public boolean execute(String action, JSONArray data, CallbackContext callbackContext) throws JSONException {

        jsResponse = new Response(callbackContext);


        //Check required permissions
        if(!permissions.hasLocationPermission()) {
            Log.i(TAG, "Location permission not allowed. Requesting.");
            permissions.requestLocationPermission();
            return true;
        }

        if(!permissions.hasBluetooth()) {
            jsResponse.send("Bluetooth not enabled", true);
            return true;
        }


        //Search for BluFi device
        if (action.equals("search")) {

            String prefix = data.getString(0);
            long timeout  = data.getLong(1);
            search.start(prefix, timeout, this);
            return true;

        } else if (action.equals("connect")) {

            try {

                JSONObject config = data.getJSONObject(0);

                identifier = config.getString("identifier");
                JSONObject UUIDS = config.getJSONObject("uuid");
                serviceUUID = UUID.fromString(UUIDS.getString("service"));
                writeUUID = UUID.fromString(UUIDS.getString("write"));
                notificationUUID = UUID.fromString(UUIDS.getString("notification"));
                MTULength = config.getInt("mtu");

                BluetoothDevice device = search.findDeviceByIdentifier(identifier);
                if(device == null) {
                    connectOnSearchResult = true;
                    search.start(Constants.BLUFI_PREFIX, Constants.DEFAULT_TIMEOUT, this);
                } else {
                    connectGatt(device);
                }
                return true;

            } catch (Exception e) {
                Log.e(TAG, "Invalid connection config" + e.toString());
                jsResponse.send("Invalid connection config", true);
                return true;
            }

        }
        else if (action.equals("configure")) {
            try {
                JSONObject config = data.getJSONObject(0);
                Configure configurator = new Configure();
                BlufiConfigureParams params = configurator.setup(config);
                configure(params);
            } catch (Exception e) {
                Log.e(TAG, e.toString());
                jsResponse.send("Invalid configuration", true);
            }
            return true;

        }
        else if (action.equals("send")) {
            String customData = data.getString(0);
            postCustomData(customData);
            return true;

        }
        else if (action.equals("disconnect")) {
            disconnectGatt();
            return true;
        }
        else if (action.equals("negotiate")) {
            negotiateSecurity();
            return true;
        }
        else if (action.equals("scan")) {
            requestDeviceWifiScan();
            return true;
        }
        else if (action.equals("status")) {
            requestDeviceStatus();
            return true;
        }
        else if (action.equals("version")) {
            requestDeviceVersion();
            return true;

        }

        return false;

    }


    public void onSearchResult(List<BluetoothDevice> devices) {

        JSONArray foundDevices = new JSONArray();
        for (BluetoothDevice device : devices) {

            Log.i(TAG, "Found "+device.getAddress());
            JSONObject currentDevice = new JSONObject();
            try {
                currentDevice.put("name", device.getName());
                currentDevice.put("address", device.getAddress());
                foundDevices.put(currentDevice);
            } catch (Exception e) {
                Log.e(TAG, e.toString());
                jsResponse.send(foundDevices, true);
            }
        }

        if(connectOnSearchResult) {

            connectOnSearchResult = false;
            BluetoothDevice device = search.findDeviceByIdentifier(identifier);
            if(device == null) {
               jsResponse.send(String.format("Device with identifier %a not found", identifier), true);
            } else {
                connectGatt(device);
            }
            
        } else {
            jsResponse.send(foundDevices, false);
        }
    }


    private void onGattConnected() {
        mConnected = true;
    }

    private void onGattDisconnected() {
        mConnected = false;
    }

    private void onGattServiceCharacteristicDiscovered() { }

    /**
     * Try to connect device
     */
    private void connectGatt(BluetoothDevice device) {

        if (mBlufiClient != null) {
            mBlufiClient.close();
            mBlufiClient = null;
        }
        if (mGatt != null) {
            mGatt.close();
        }

        mDevice = device;

        GattCallback callback = new GattCallback();
        if (SdkUtil.isAtLeastM()) {
            mGatt = mDevice.connectGatt(this.context, false, callback, BluetoothDevice.TRANSPORT_LE);
        } else {
            mGatt = mDevice.connectGatt(this.context, false, callback);
        }
    }

    /**
     * Request device disconnect the connection.
     */
    private void disconnectGatt() {
        if(!mConnected) {
            jsResponse.send("Not connected", true);
            return;
        }
        if (mBlufiClient != null) {
            mBlufiClient.requestCloseConnection();
        }
    }

    /**
     * If negotiate security success, the continue communication data will be encrypted.
     */
    private void negotiateSecurity() {
        if(!mConnected) {
            jsResponse.send("Not connected", true);
            return;
        }
        mBlufiClient.negotiateSecurity();
    }

    /**
     * Request to configure station or softap
     *
     * @param params configure params
     */
    private void configure(BlufiConfigureParams params) {
        if(!mConnected) {
            jsResponse.send("Not connected", true);
            return;
        }
        mBlufiClient.configure(params);
    }

    /**
     * Request to get device current status
     */
    private void requestDeviceStatus() {
        if(!mConnected) {
            jsResponse.send("Not connected", true);
            return;
        }
        mBlufiClient.requestDeviceStatus();
    }

    /**
     * Request to get device blufi version
     */
    private void requestDeviceVersion() {
        if(!mConnected) {
            jsResponse.send("Not connected", true);
            return;
        }
        mBlufiClient.requestDeviceVersion();
    }

    /**
     * Request to get AP list that the device scanned
     */
    private void requestDeviceWifiScan() {
        if(!mConnected) {
            jsResponse.send("Not connected", true);
            return;
        }
        mBlufiClient.requestDeviceWifiScan();
    }

    /**
     * Try to post custom data
     */
    private void postCustomData(String dataString) {
        if(!mConnected) {
            jsResponse.send("Not connected", true);
            return;
        }
       mBlufiClient.postCustomData(dataString.getBytes());
    }








    /**
     * mBlufiClient call onCharacteristicWrite and onCharacteristicChanged is required
     */
    private class GattCallback extends BluetoothGattCallback {

        @Override
        public void onConnectionStateChange(BluetoothGatt gatt, int status, int newState) {
            String devAddr = gatt.getDevice().getAddress();
            Log.i("BLUFI", String.format(Locale.ENGLISH, "onConnectionStateChange addr=%s, status=%d, newState=%d", devAddr, status, newState));
            if (status == BluetoothGatt.GATT_SUCCESS) {
                switch (newState) {
                    case BluetoothProfile.STATE_CONNECTED:
                        gatt.discoverServices();
                        onGattConnected();
                        try {
                            JSONObject result = new JSONObject();
                            result.put("message", "Connected");
                            result.put("connected", true);
                            result.put( "address", devAddr);
                            result.put( "error", "");
                            jsResponse.send(result, false);
                        } catch (Exception e) {
                            jsResponse.send("General error: "+e.toString(), true);
                        }
                        break;
                    case BluetoothProfile.STATE_DISCONNECTED:
                        gatt.close();
                        onGattDisconnected();
                        try {
                            JSONObject result = new JSONObject();
                            result.put("message", "Device disconnected");
                            result.put("connected", false);
                            result.put( "address", devAddr);
                            result.put( "error", "");
                            jsResponse.send(result, false);
                        } catch (Exception e) {
                            jsResponse.send("General error: "+e.toString(), true);
                        }
                        break;
                }
            } else {
                gatt.close();
                onGattDisconnected();
                try {
                    JSONObject result = new JSONObject();
                    result.put("message", "Device disconnected");
                    result.put("connected", false);
                    result.put( "address", devAddr);
                    result.put( "error", status);
                    jsResponse.send(result, false);
                } catch (Exception e) {
                    jsResponse.send("General error: "+e.toString(), true);
                }
            }
        }

        @Override
        public void onServicesDiscovered(BluetoothGatt gatt, int status) {
            Log.i("BLUFI", String.format(Locale.ENGLISH, "onServicesDiscovered status=%d", status));
            if (status == BluetoothGatt.GATT_SUCCESS) {
                BluetoothGattService service = gatt.getService(serviceUUID);
                if (service == null) {
                    Log.w("BLUFI", "Discover service failed");
                    gatt.disconnect();
                    jsResponse.send("Discover service failed", true);
                    return;
                }

                BluetoothGattCharacteristic writeCharact = service.getCharacteristic(writeUUID);
                if (writeCharact == null) {
                    Log.w("BLUFI", "Get write characteristic failed");
                    gatt.disconnect();
                    jsResponse.send("Get write characteristic failed", false);
                    return;
                }

                BluetoothGattCharacteristic notifyCharact = service.getCharacteristic(notificationUUID);
                if (notifyCharact == null) {
                    Log.w("BLUFI", "Get notification characteristic failed");
                    gatt.disconnect();
                    jsResponse.send("Get notification characteristic failed", false);
                    return;
                }

                jsResponse.send("Discover service and characteristics success", false);

                if (mBlufiClient != null) {
                    mBlufiClient.close();
                }
                mBlufiClient = new BlufiClient(gatt, writeCharact, notifyCharact, new BlufiCallbackMain());

                gatt.setCharacteristicNotification(notifyCharact, true);

                if (SdkUtil.isAtLeastL()) {
                    gatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);
                    int mtu = (int) MTULength;
                    boolean requestMtu = gatt.requestMtu(mtu);
                    if (!requestMtu) {
                        Log.w("BLUFI", "Request mtu failed");
                        jsResponse.send(String.format(Locale.ENGLISH, "Request mtu %d failed", mtu), false);
                        onGattServiceCharacteristicDiscovered();
                    }
                }
            } else {
                gatt.disconnect();
                jsResponse.send(String.format(Locale.ENGLISH, "Discover services error status %d", status), false);
            }
        }

        @Override
        public void onMtuChanged(BluetoothGatt gatt, int mtu, int status) {
            Log.i("BLUFI", String.format(Locale.ENGLISH, "onMtuChanged status=%d, mtu=%d", status, mtu));
            if (status == BluetoothGatt.GATT_SUCCESS) {
                jsResponse.send(String.format(Locale.ENGLISH, "Set mtu %d complete", mtu), false);
            } else {
                jsResponse.send(String.format(Locale.ENGLISH, "Set mtu %d error status %d", mtu, status), false);
            }
            onGattServiceCharacteristicDiscovered();
        }

        @Override
        public void onCharacteristicWrite(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
            Log.i("BLUFI","onCharacteristicWrite " + status);
            // This is requirement
            mBlufiClient.onCharacteristicWrite(gatt, characteristic, status);
        }

        @Override
        public void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic) {
            Log.i("BLUFI","onCharacteristicChanged");
            // This is requirement
            mBlufiClient.onCharacteristicChanged(gatt, characteristic);
        }
    }

    private class BlufiCallbackMain extends BlufiCallback {
        @Override
        public void onNegotiateSecurityResult(BlufiClient client, int status) {
            switch (status) {
                case STATUS_SUCCESS:
                    try {
                        JSONObject result = new JSONObject();
                        result.put("message", "Security negotiation complete");
                        result.put( "error", "");
                        result.put("complete", true);
                        jsResponse.send(result, false);
                    } catch (Exception e) {
                        jsResponse.send("General error: "+e.toString(), true);
                    }
                    break;
                default:
                    try {
                        JSONObject result = new JSONObject();
                        result.put("message", "Security negotiation failed");
                        result.put( "error", status);
                        result.put("complete", false);
                        jsResponse.send(result, true);
                    } catch (Exception e) {
                        jsResponse.send("General error: "+e.toString(), true);
                    }
                    break;
            }

        }

        @Override
        public void onConfigureResult(BlufiClient client, int status) {
            switch (status) {
                case STATUS_SUCCESS:
                    try {
                        JSONObject result = new JSONObject();
                        result.put("message", "Configuration complete");
                        result.put( "error", "");
                        result.put("complete", true);
                        jsResponse.send(result, false);
                    } catch (Exception e) {
                        jsResponse.send("General error: "+e.toString(), true);
                    }                    break;
                default:
                    try {
                        JSONObject result = new JSONObject();
                        result.put("message", "Configuration failed");
                        result.put( "error", status);
                        result.put("complete", false);
                        jsResponse.send(result, true);
                    } catch (Exception e) {
                        jsResponse.send("General error: "+e.toString(), true);
                    }
                    break;
            }

        }

        @Override
        public void onDeviceStatusResponse(BlufiClient client, int status, BlufiStatusResponse response) {
            Log.i(TAG, "Device Status Response : " + Integer.toString(status));
            Log.i(TAG, "Device Response : " + response.generateValidInfo());

            switch (status) {
                case STATUS_SUCCESS:
                    try {
                        JSONObject result = new JSONObject();
                        result.put("opMode", response.getOpMode());
                        result.put("stationState", response.getStaConnectionStatus() == 0 ? "Connected" : "Disconnected");
                        result.put("softAPState", response.getSoftAPConnectionCount());
                        result.put("softAPSSID", response.getSoftAPSSID());
                        result.put("error", "");
                        result.put("message", "Get status successful");
                        jsResponse.send(result, false);
                    } catch (Exception e) {
                        jsResponse.send("General error: ", true);
                    }
                    break;
                default:
                    try {
                        JSONObject result = new JSONObject();
                        result.put("opMode", response.getOpMode());
                        result.put("stationState", response.getStaConnectionStatus() == 0 ? "Connected" : "Disconnected");
                        result.put("softAPState", response.getSoftAPConnectionCount());
                        result.put("softAPSSID", response.getSoftAPSSID());
                        result.put("error", status);
                        result.put("message", "Get status failed");
                        jsResponse.send(result, true);
                    } catch (Exception e) {
                        jsResponse.send("General error:"+e.toString(), true);
                    }
                    break;
            }

        }

        @Override
        public void onDeviceScanResult(BlufiClient client, int status, List<BlufiScanResult> results) {
            switch (status) {
                case STATUS_SUCCESS:
                    try {
                        JSONArray response = new JSONArray();
                        for (BlufiScanResult scanResult : results) {
                            JSONObject result = new JSONObject();
                            result.put("ssid", scanResult.getSsid());
                            result.put("rssi", scanResult.getRssi());
                            response.put(result);
                        }
                        jsResponse.send(response, false);
                    } catch (Exception e) {
                        jsResponse.send("General error:"+e.toString(), true);
                    }

                    break;
                default:
                    try {
                        JSONArray response = new JSONArray();
                        jsResponse.send(response, true);
                    } catch (Exception e) {
                        jsResponse.send("General error:"+e.toString(), true);
                    }
                    break;
            }

        }

        @Override
        public void onDeviceVersionResponse(BlufiClient client, int status, BlufiVersionResponse response) {
            switch (status) {
                case STATUS_SUCCESS:
                    try {
                        JSONObject result = new JSONObject();
                        result.put("message", "Get version successful");
                        result.put( "error", "");
                        result.put("version", response.getVersionString());

                        jsResponse.send(result, false);
                    } catch (Exception e) {
                        jsResponse.send("General error: "+e.toString(), true);
                    }
                    break;
                default:
                    try {
                        JSONObject result = new JSONObject();
                        result.put("message", "Get version failed");
                        result.put( "error", status);
                        result.put("version", "");
                        jsResponse.send(result, true);
                    } catch (Exception e) {
                        jsResponse.send("General error: "+e.toString(), true);
                    }
                    break;
            }
        }

        @Override
        public void onPostCustomDataResult(BlufiClient client, int status, byte[] data) {
            String dataStr = new String(data);
            String format = "Post data %s %s";
            switch (status) {
                case STATUS_SUCCESS:
                    try {
                        JSONObject result = new JSONObject();
                        result.put("message", "Send custom data complete");
                        result.put( "error", "");
                        result.put("complete", true);
                        jsResponse.send(result, false);
                    } catch (Exception e) {
                        jsResponse.send("General error: "+e.toString(), true);
                    }
                    break;
                default:
                    try {
                        JSONObject result = new JSONObject();
                        result.put("message", "Send custom data failed");
                        result.put( "error", status);
                        result.put("complete", false);
                        jsResponse.send(result, true);
                    } catch (Exception e) {
                        jsResponse.send("General error: "+e.toString(), true);
                    }
                    break;
            }
        }

        @Override
        public void onReceiveCustomData(BlufiClient client, int status, byte[] data) {
            switch (status) {
                case STATUS_SUCCESS:
                    String customStr = new String(data);
                    jsResponse.send(String.format("Receive custom data:\n%s", customStr), false);
                    break;
                default:
                    jsResponse.send("Receive custom data error", true);
                    break;
            }
        }

        @Override
        public void onError(BlufiClient client, int errCode) {
            jsResponse.send(String.format(Locale.ENGLISH, "Receive error code %d", errCode), true);
        }
    }

}
