package za.co.clearcell.blufi;

import android.bluetooth.BluetoothDevice;
import android.os.SystemClock;
import android.text.TextUtils;
import android.util.Log;

import org.apache.cordova.CordovaInterface;
import org.apache.cordova.CordovaPlugin;

import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import libs.espressif.ble.EspBleClient;
import libs.espressif.ble.ScanListener;

public class Search {


    private String TAG = "BluFi:Search";
    private CordovaInterface cordova;
    private CordovaPlugin plugin;

    private Map<BluetoothDevice, Integer> mDeviceRssiMap;
    private List<BluetoothDevice> mBleList;
    private ExecutorService mThreadPool;
    private Future mUpdateFuture;
    private Boolean stopThread = false;
    private String mBlufiFilter;
    private volatile long mScanStartTime;
    private ScanCallback mScanCallback;
    private List<BluetoothDevice> devices;
    private SearchResultEvent result;



    public Search(CordovaInterface cordova, CordovaPlugin plugin) {
        this.cordova = cordova;
        this.plugin = plugin;

        mThreadPool = Executors.newSingleThreadExecutor();
        mBleList = new LinkedList<>();
        mDeviceRssiMap = new HashMap<>();
        mScanCallback = new ScanCallback();
    }

    public void start(String prefix, long timeout,  SearchResultEvent event) {

        Log.i(TAG, "Searching "+prefix+" ("+timeout+")");

        this.result = event;

        mDeviceRssiMap.clear();
        mBleList.clear();
        mBlufiFilter = prefix;
        mScanStartTime = SystemClock.elapsedRealtime();

        Log.i(TAG, "Start scan BLE");
        EspBleClient.startScanBle(mScanCallback);
        stopThread = false;
        mUpdateFuture = mThreadPool.submit(() -> {
            while (!Thread.currentThread().isInterrupted() && !stopThread) {
                try {
                    Thread.sleep(1000);
                } catch (InterruptedException e) {
                    e.printStackTrace();
                    break;
                }

                long scanCost = SystemClock.elapsedRealtime() - mScanStartTime;
                if (scanCost > timeout) {
                    break;
                }

                onIntervalScanUpdate();
            }

            EspBleClient.stopScanBle(mScanCallback);
            onIntervalScanUpdate();
            Log.d("BLUFI", "Scan BLE thread is done");
        });
    }

    public BluetoothDevice findDeviceByIdentifier(String identifier) {
        Log.i(TAG, "findDeviceByIdentifier : "+identifier);
        if(devices == null) {
            return null;
        }
        for (BluetoothDevice device : devices) {
            if ( ((device.getAddress() != null) && device.getAddress().equals(identifier)) || ( (device.getName() != null) && device.getName().equals(identifier))) {
                Log.i(TAG, "Device Found : " + device.getAddress() + "/" + device.getName());
                return device;
            }
        }
        return null;
    }

    private void onIntervalScanUpdate() {
        devices = new LinkedList<>(mDeviceRssiMap.keySet());
        Collections.sort(devices, (dev1, dev2) -> {
            Integer rssi1 = mDeviceRssiMap.get(dev1);
            Integer rssi2 = mDeviceRssiMap.get(dev2);
            return rssi2.compareTo(rssi1);
        });

        result.onSearchResult(devices);
    }

    private class ScanCallback implements ScanListener {

        @Override
        public void onLeScan(BluetoothDevice device, int rssi, byte[] scanRecord) {
            String name = device.getName();
            if (!TextUtils.isEmpty(mBlufiFilter)) {
                if (name == null || !name.startsWith(mBlufiFilter)) {
                    return;
                }
            }

            mDeviceRssiMap.put(device, rssi);
        }
    }

}
