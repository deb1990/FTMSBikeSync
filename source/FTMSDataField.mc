// FTMSDataField.mc
// Full-screen Data Field for the Garmin Fenix 7 Pro.
//
// Layout (260x260):
//   Row 1 — HR Zone (coloured background + white label/value)
//   Row 2 — Distance (left) | Speed (right)
//   Row 3 — Power (left)    | Cadence (right)
//   Row 4 — Activity Timer
//
// Standard FIT Record field IDs:
//   4 = cadence  (UINT8,  rpm,  scale 1)
//   5 = distance (UINT32, m,    scale 100  → store value * 100)
//   6 = speed    (UINT16, m/s,  scale 1000 → store value * 1000)
//   7 = power    (UINT16, W,    scale 1)

import Toybox.WatchUi;
import Toybox.Activity;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.UserProfile;

// Standard FIT Record field IDs
const FIT_FIELD_CADENCE  = 4;
const FIT_FIELD_DISTANCE = 5;
const FIT_FIELD_SPEED    = 6;
const FIT_FIELD_POWER    = 7;

// -----------------------------------------------------------------------
// Set USE_MOCK_DATA = true to test UI in the simulator (no BLE needed).
// Set to false before deploying to the watch.
// -----------------------------------------------------------------------
const USE_MOCK_DATA = true;

// Mock delegate — same public interface as FTMSBleDelegate but no BLE calls.
// Used in the simulator so the UI can be tested without crashing.
class FTMSMockDelegate {
    var speedKph   = 28.4f;
    var cadenceRpm = 85.0f;
    var distanceM  = 12340;
    var powerW     = 247;
    function getState() { return STATE_CONNECTED; }
}

class FTMSDataField extends WatchUi.DataField {

    // BLE delegate — owns connection and live metric values
    var _ble;

    // FIT contributor fields
    var _fitCadence;
    var _fitDistance;
    var _fitSpeed;
    var _fitPower;

    // Cached values from Activity.Info (not available in onUpdate)
    var _heartRate = 0;
    var _timerMs   = 0;
    var _mockHr    = 60;  // slowly drifts 60→200→60 in simulator

    // -----------------------------------------------------------------------
    // initialize
    // -----------------------------------------------------------------------
    function initialize() {
        DataField.initialize();

        _ble = USE_MOCK_DATA ? new FTMSMockDelegate() : new FTMSBleDelegate();

        _fitCadence = createField(
            "cadence", 0, FitContributor.DATA_TYPE_UINT8,
            { :nativeNum => FIT_FIELD_CADENCE, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "rpm" }
        );
        _fitDistance = createField(
            "distance", 1, FitContributor.DATA_TYPE_UINT32,
            { :nativeNum => FIT_FIELD_DISTANCE, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "m" }
        );
        _fitSpeed = createField(
            "speed", 2, FitContributor.DATA_TYPE_UINT16,
            { :nativeNum => FIT_FIELD_SPEED, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "m/s" }
        );
        _fitPower = createField(
            "power", 3, FitContributor.DATA_TYPE_UINT16,
            { :nativeNum => FIT_FIELD_POWER, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W" }
        );
    }

    // -----------------------------------------------------------------------
    // compute — called each recording interval (~1 s)
    // -----------------------------------------------------------------------
    function compute(info as Activity.Info) as Object or Null {
        // Cache HR and timer for use in onUpdate
        if (USE_MOCK_DATA) {
            _mockHr = _mockHr + 5;
            if (_mockHr > 200) { _mockHr = 60; }
            _heartRate = _mockHr;
        } else if (info.currentHeartRate != null) {
            _heartRate = info.currentHeartRate;
        }
        if (info.timerTime != null) {
            _timerMs = info.timerTime;
        }

        // Write BLE metrics to FIT file (skipped in mock/simulator mode)
        if (!USE_MOCK_DATA) {
            var speedKph   = _ble.speedKph;
            var cadenceRpm = _ble.cadenceRpm;
            var distanceM  = _ble.distanceM;
            var powerW     = _ble.powerW;

            _fitSpeed.setData((speedKph / 3.6f * 1000.0f).toNumber());
            _fitDistance.setData(distanceM * 100);

            var cadenceInt = Math.round(cadenceRpm).toNumber();
            if (cadenceInt < 0)   { cadenceInt = 0; }
            if (cadenceInt > 255) { cadenceInt = 255; }
            _fitCadence.setData(cadenceInt);

            var powerInt = powerW;
            if (powerInt < 0)     { powerInt = 0; }
            if (powerInt > 65535) { powerInt = 65535; }
            _fitPower.setData(powerInt);
        }

        return null;
    }

    // -----------------------------------------------------------------------
    // onUpdate — draw the full screen
    // -----------------------------------------------------------------------
    function onUpdate(dc as Graphics.Dc) as Void {
        var h    = dc.getHeight();
        var w    = dc.getWidth();
        var mid  = w / 2;
        var colL = w / 4;
        var colR = (w * 3) / 4;

        // Row dividers: 27% / 23% / 23% / 27%
        var div1 = h * 27 / 100;
        var div2 = h * 50 / 100;
        var div3 = h * 73 / 100;

        // Font heights for vertical centering
        var tinyH = dc.getFontHeight(Graphics.FONT_XTINY);
        var medH  = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var gap   = -2;

        // White background
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.clear();

        // ---- Row 1: HR Zone Background (27%) --------------------------------
        var zoneColor;
        var zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_BIKING);
        if (_heartRate <= 0 || zones == null) {
            zoneColor = Graphics.COLOR_LT_GRAY;
        } else if (_heartRate <= zones[0]) {
            zoneColor = Graphics.COLOR_LT_GRAY;   // zone 1 — warm up
        } else if (_heartRate <= zones[1]) {
            zoneColor = Graphics.COLOR_BLUE;       // zone 2 — easy
        } else if (_heartRate <= zones[2]) {
            zoneColor = Graphics.COLOR_GREEN;      // zone 3 — aerobic
        } else if (_heartRate <= zones[3]) {
            zoneColor = Graphics.COLOR_ORANGE;     // zone 4 — threshold
        } else {
            zoneColor = Graphics.COLOR_RED;        // zone 5 — maximum
        }

        dc.setColor(zoneColor, zoneColor);
        dc.fillRectangle(0, 0, w, div1);

        var hotH  = dc.getFontHeight(Graphics.FONT_NUMBER_MEDIUM);
        var r1VY  = (div1 - hotH) / 2;
        var hrTextColor = (zoneColor == Graphics.COLOR_LT_GRAY)
            ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;
        dc.setColor(hrTextColor, Graphics.COLOR_TRANSPARENT);
        var hrStr = (_heartRate > 0) ? _heartRate.toString() : "--";
        dc.drawText(mid, r1VY, Graphics.FONT_NUMBER_MEDIUM, hrStr, Graphics.TEXT_JUSTIFY_CENTER);

        // ---- Divider 1 ------------------------------------------------------
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(15, div1, w - 15, div1);

        // ---- Row 2: Distance | Speed (23%) ----------------------------------
        var r2LY = div1 + (div2 - div1 - tinyH - gap - medH) / 2;
        var r2VY = r2LY + tinyH + gap;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colL, r2LY, Graphics.FONT_XTINY, "DIST (km)",    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colR, r2LY, Graphics.FONT_XTINY, "SPD (km/h)", Graphics.TEXT_JUSTIFY_CENTER);

        var distM    = _ble.distanceM;
        var speedKph = _ble.speedKph;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colL, r2VY, Graphics.FONT_MEDIUM,
            (distM / 1000.0f).format("%.2f"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colR, r2VY, Graphics.FONT_MEDIUM,
            speedKph.format("%.1f"),           Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(mid, div1 + 1, mid, div2);

        // ---- Divider 2 ------------------------------------------------------
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(15, div2, w - 15, div2);

        // ---- Row 3: Power | Cadence (23%) -----------------------------------
        var r3LY = div2 + (div3 - div2 - tinyH - gap - medH) / 2;
        var r3VY = r3LY + tinyH + gap;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colL, r3LY, Graphics.FONT_XTINY, "PWR (W)",     Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colR, r3LY, Graphics.FONT_XTINY, "CAD (rpm)", Graphics.TEXT_JUSTIFY_CENTER);

        var powerW     = _ble.powerW;
        var cadenceRpm = _ble.cadenceRpm;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colL, r3VY, Graphics.FONT_MEDIUM,
            powerW.toString(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colR, r3VY, Graphics.FONT_MEDIUM,
            Math.round(cadenceRpm).toNumber().toString(), Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(mid, div2 + 1, mid, div3);

        // ---- Divider 3 ------------------------------------------------------
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(15, div3, w - 15, div3);

        // ---- Row 4: Timer (27%) --------------------------------------------
        var r4LY = div3 + (h - div3 - tinyH - gap - medH) / 2;
        var r4VY = r4LY + tinyH + gap;

        var timerLabel = "TIMER";
        var statusDot  = " \u25CF";
        var labelW = dc.getTextWidthInPixels(timerLabel, Graphics.FONT_XTINY);
        var dotW   = dc.getTextWidthInPixels(statusDot,  Graphics.FONT_XTINY);
        var startX = mid - (labelW + dotW) / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX, r4LY, Graphics.FONT_XTINY, timerLabel, Graphics.TEXT_JUSTIFY_LEFT);

        var bleState = _ble.getState();
        var dotColor = (bleState == STATE_CONNECTED) ? Graphics.COLOR_GREEN : Graphics.COLOR_YELLOW;
        dc.setColor(dotColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + labelW, r4LY, Graphics.FONT_XTINY, statusDot, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(mid, r4VY, Graphics.FONT_MEDIUM, _formatTimer(_timerMs),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // -----------------------------------------------------------------------
    // _formatTimer — ms → "MM:SS" or "H:MM:SS"
    // -----------------------------------------------------------------------
    function _formatTimer(ms as Number) as String {
        var s = (ms / 1000).toNumber();
        var h = s / 3600;
        var m = (s % 3600) / 60;
        var sec = s % 60;

        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + sec.format("%02d");
        }
        return m.format("%02d") + ":" + sec.format("%02d");
    }

}
