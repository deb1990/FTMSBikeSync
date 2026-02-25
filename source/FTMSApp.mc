// FTMSApp.mc
// Minimal AppBase entry point for FTMSBikeSync.
// The entire app logic lives in FTMSDataField and FTMSBleDelegate.

import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class FTMSApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // Return the initial view — a single full-screen Data Field.
    function getInitialView() as [ WatchUi.Views ] or [ WatchUi.Views, WatchUi.InputDelegates ] {
        return [ new FTMSDataField() ];
    }

}

// Application entry point required by Connect IQ runtime
function getApp() as FTMSApp {
    return Application.getApp() as FTMSApp;
}
