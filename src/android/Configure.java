package za.co.clearcell.blufi;

import android.util.Log;

import org.json.JSONObject;

import blufi.espressif.params.BlufiConfigureParams;
import blufi.espressif.params.BlufiParameter;

public class Configure {

    private String TAG = "BLUFI:CONFIGURE";

    private BlufiConfigureParams params;

    private static final int OP_MODE_POS_STA = 0;
    private static final int OP_MODE_POS_SOFTAP = 1;
    private static final int OP_MODE_POS_STASOFTAP = 2;

    private static final int[] OP_MODE_VALUES = {
            BlufiParameter.OP_MODE_STA,
            BlufiParameter.OP_MODE_SOFTAP,
            BlufiParameter.OP_MODE_STASOFTAP
    };

    public BlufiConfigureParams setup(JSONObject config) {

        BlufiConfigureParams params = new BlufiConfigureParams();

        try {

            String mode = config.getString("mode");
            JSONObject modeConfig = config.getJSONObject("config");

            if(mode.equals("station")) {
                params = setupStation(params, modeConfig);
            } else if(mode.equals("softap")) {
                params = setupSoftAP(params, modeConfig);
            } else if(mode.equals("stasoftap")) {

                JSONObject stationConfig = modeConfig.getJSONObject("station");
                JSONObject softAPConfig = modeConfig.getJSONObject("softap");

                params = setupStation(params, stationConfig);
                params = setupSoftAP(params, softAPConfig);

                params.setOpMode(OP_MODE_VALUES[OP_MODE_POS_STASOFTAP]);
            }


        } catch (Exception e) {
            Log.e(TAG, "Error processing configuration : "+e.toString());
            return null;
        }


        return params;
    }



    private BlufiConfigureParams setupStation(BlufiConfigureParams params, JSONObject config) {
        try {

            String ssid = config.getString("ssid");
            String password = config.getString("password");

            params.setOpMode(OP_MODE_VALUES[OP_MODE_POS_STA]);
            params.setStaSSID(ssid);
            params.setStaPassword(password);

            return params;

        } catch (Exception e) {
            Log.e(TAG, e.toString());
            return null;
        }
    }

    private BlufiConfigureParams setupSoftAP(BlufiConfigureParams params, JSONObject config) {

        params = new BlufiConfigureParams();

        try {

            String ssid = config.getString("ssid");
            int channel = config.getInt("channel");
            int maxConnections = config.getInt("maxConnections");

            params.setOpMode(OP_MODE_VALUES[OP_MODE_POS_SOFTAP]);
            params.setSoftAPSSID(ssid);
            params.setSoftAPChannel(channel);
            params.setSoftAPMaxConnection(maxConnections);

            String security = config.getString("security");

            if(!security.equals("open")) {
                if(security.equals("wpa-psk")) {
                  params.setSoftAPSecurity(BlufiParameter.SOFTAP_SECURITY_WPA);
                } else if(security.equals("wpa2-psk")) {
                    params.setSoftAPSecurity(BlufiParameter.SOFTAP_SECURITY_WPA2);
                } else if(security.equals("wpa-wap2-psk")) {
                    params.setSoftAPSecurity(BlufiParameter.SOFTAP_SECURITY_WPA_WPA2);
                }
                String password = config.getString("password");
                params.setSoftAPPAssword(password);
            } else {
                params.setSoftAPSecurity(BlufiParameter.SOFTAP_SECURITY_OPEN);
            }

            return params;

        } catch (Exception e) {
            Log.e(TAG, e.toString());
            return null;
        }
    }
}
