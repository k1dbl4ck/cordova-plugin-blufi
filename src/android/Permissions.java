package za.co.clearcell.blufi;

import android.Manifest;
import android.bluetooth.BluetoothAdapter;
import android.util.Log;

import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;

public class Permissions {

    private String TAG = "BluFi:Permissions";
    private CordovaInterface cordova;
    private CordovaPlugin plugin;

    private static final String COARSE_LOCATION = Manifest.permission.ACCESS_COARSE_LOCATION;
    private static final String FINE_LOCATION = Manifest.permission.ACCESS_FINE_LOCATION;


    public Permissions(CordovaInterface cordova, CordovaPlugin plugin) {
        this.cordova = cordova;
        this.plugin = plugin;
    }

    public Boolean hasLocationPermission() {

        if(cordova.hasPermission(COARSE_LOCATION) && cordova.hasPermission(FINE_LOCATION)) {
            return true;
        } else {
            return false;
        }
    }

    public void requestLocationPermission() {
        cordova.requestPermission(plugin, 0, FINE_LOCATION);
    }

    public Boolean hasBluetooth() {

        if (!BluetoothAdapter.getDefaultAdapter().isEnabled()) {
            Log.w(TAG, "Bluetooth not enabled");
            return false;
        } else {
            return true;
        }

    }

}
