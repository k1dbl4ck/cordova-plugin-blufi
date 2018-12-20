package za.co.clearcell.blufi;


import android.bluetooth.BluetoothDevice;

import java.util.List;

public interface SearchResultEvent
{
    public void onSearchResult(List<BluetoothDevice> devices);
}


