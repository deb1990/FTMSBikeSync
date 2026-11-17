// FTMSConstants.mc
// Shared constants (connection states, storage keys).

enum {
    STATE_SCANNING      = 0,
    STATE_CONNECTING    = 1,
    STATE_CONNECTED     = 2,
    STATE_RECONNECTING  = 3
}

const STORAGE_KEY_DEVICE_NAME = "lastFtmsDeviceName";
