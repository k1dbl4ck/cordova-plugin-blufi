package za.co.clearcell.blufi;

import org.apache.cordova.CallbackContext;
import org.json.JSONArray;
import org.json.JSONObject;

public class Response {

    CallbackContext callbackContext;
    public Response(CallbackContext callbackContext) {
        this.callbackContext = callbackContext;
    }

    public void send(String message, boolean isError) {

        if (isError) {
            callbackContext.error(message);
        } else {
            callbackContext.success(message);
        }
    }

    public void send(JSONObject message, boolean isError) {

        if (isError) {
            callbackContext.error(message);
        } else {
            callbackContext.success(message);
        }
    }

    public void send(JSONArray message, boolean isError) {

        if (isError) {
            callbackContext.error(message.toString());
        } else {
            callbackContext.success(message);
        }
    }

}
