// FTMSDataField.mc
// Full-screen Data Field for the Garmin Fenix 7 Pro.
//
// Layout:
//   Row 1 (27%) — HR with zone-coloured background
//   Row 2 (23%) — Distance (left) | Speed (right)
//   Row 3 (23%) — Power (left)    | Cadence (right)
//   Row 4 (27%) — Activity Timer
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

const FIT_FIELD_CADENCE  = 4;
const FIT_FIELD_DISTANCE = 5;
const FIT_FIELD_SPEED    = 6;
const FIT_FIELD_POWER    = 7;

// -----------------------------------------------------------------------
// Set USE_MOCK_DATA = true to test UI in the simulator (no BLE needed).
// Set to false before deploying to the watch.
// -----------------------------------------------------------------------
const USE_MOCK_DATA = false;

// Mock delegate — same public interface as FTMSBleDelegate but no BLE calls.
class FTMSMockDelegate {
    var speedKph   = 28.4f;
    var cadenceRpm = 85.0f;
    var distanceM  = 12340;
    var powerW     = 247;
    function getState() { return STATE_CONNECTED; }
}

class FTMSDataField extends WatchUi.DataField {

    var _ble;
    var _fitCadence;
    var _fitDistance;
    var _fitSpeed;
    var _fitPower;
    var _heartRate = 0;
    var _timerMs   = 0;
    var _mockHr    = 60;

    // -----------------------------------------------------------------------
    // initialize
    // -----------------------------------------------------------------------
    function initialize() {
        DataField.initialize();
        _ble = USE_MOCK_DATA ? new FTMSMockDelegate() : new FTMSBleDelegate();
        _fitCadence = createField(
            "cadence", 0, FitContributor.DATA_TYPE_UINT8,
            { :nativeNum => FIT_FIELD_CADENCE, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "rpm", :displayInChart => true }
        );
        _fitDistance = createField(
            "distance", 1, FitContributor.DATA_TYPE_UINT32,
            { :nativeNum => FIT_FIELD_DISTANCE, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "m", :displayInChart => true }
        );
        _fitSpeed = createField(
            "speed", 2, FitContributor.DATA_TYPE_UINT16,
            { :nativeNum => FIT_FIELD_SPEED, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "m/s", :displayInChart => true }
        );
        _fitPower = createField(
            "power", 3, FitContributor.DATA_TYPE_UINT16,
            { :nativeNum => FIT_FIELD_POWER, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W", :displayInChart => true }
        );
    }

    // -----------------------------------------------------------------------
    // compute — called each recording interval (~1 s)
    // -----------------------------------------------------------------------
    function compute(info as Activity.Info) as Object or Null {
        if (USE_MOCK_DATA) {
            _mockHr = _mockHr + 5;
            if (_mockHr > 260) { _mockHr = 60; }
            _heartRate = _mockHr;
        } else if (info.currentHeartRate != null) {
            _heartRate = info.currentHeartRate;
        }
        if (info.timerTime != null) {
            _timerMs = info.timerTime;
        }
        if (!USE_MOCK_DATA) {
            _writeFitFields();
        }
        return null;
    }

    // -----------------------------------------------------------------------
    // onUpdate — orchestrates drawing
    // -----------------------------------------------------------------------
    function onUpdate(dc as Graphics.Dc) as Void {
        var h    = dc.getHeight();
        var w    = dc.getWidth();
        var mid  = w / 2;
        var colL = w / 4;
        var colR = (w * 3) / 4;
        var div1 = h * 27 / 100;
        var div2 = h * 50 / 100;
        var div3 = h * 73 / 100;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.clear();

        _drawHrRow(dc, w, mid, div1);
        _drawDivider(dc, w, div1);
        _drawDistSpeedRow(dc, w, mid, colL, colR, div1, div2);
        _drawDivider(dc, w, div2);
        _drawPowerCadenceRow(dc, w, mid, colL, colR, div2, div3);
        _drawDivider(dc, w, div3);
        _drawTimerRow(dc, w, mid, div3, h);
    }

    // -----------------------------------------------------------------------
    // _getZoneColor — returns background colour for current HR zone
    // -----------------------------------------------------------------------
    hidden function _getZoneColor() as Graphics.ColorType {
        var zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_BIKING);
        if (_heartRate <= 0 || zones == null) { return Graphics.COLOR_LT_GRAY; }
        if (_heartRate <= zones[1])           { return Graphics.COLOR_LT_GRAY; }
        if (_heartRate <= zones[2])           { return Graphics.COLOR_BLUE;    }
        if (_heartRate <= zones[3])           { return Graphics.COLOR_GREEN;   }
        if (_heartRate <= zones[4])           { return Graphics.COLOR_ORANGE;  }
        return Graphics.COLOR_RED;
    }

    // -----------------------------------------------------------------------
    // _centeredLabelY — top Y for a label+gap+value block centred in a row
    // -----------------------------------------------------------------------
    hidden function _centeredLabelY(rowTop as Number, rowBottom as Number,
                                    labelH as Number, valueH as Number,
                                    gap as Number) as Number {
        return rowTop + (rowBottom - rowTop - labelH - gap - valueH) / 2;
    }

    // -----------------------------------------------------------------------
    // _drawDivider — horizontal rule across the screen
    // -----------------------------------------------------------------------
    hidden function _drawDivider(dc as Graphics.Dc, w as Number, y as Number) as Void {
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(15, y, w - 15, y);
    }

    // -----------------------------------------------------------------------
    // _drawHrRow — zone-coloured background + large HR number
    // -----------------------------------------------------------------------
    hidden function _drawHrRow(dc as Graphics.Dc, w as Number,
                                mid as Number, rowBottom as Number) as Void {
        var zoneColor = _getZoneColor();
        dc.setColor(zoneColor, zoneColor);
        dc.fillRectangle(0, 0, w, rowBottom);

        var fontH     = dc.getFontHeight(Graphics.FONT_NUMBER_MEDIUM);
        var y         = (rowBottom - fontH) / 2;
        var textColor = (zoneColor == Graphics.COLOR_LT_GRAY)
            ? Graphics.COLOR_BLACK : Graphics.COLOR_WHITE;
        var hrStr     = (_heartRate > 0) ? _heartRate.toString() : "--";

        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(mid, y, Graphics.FONT_NUMBER_MEDIUM, hrStr, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // -----------------------------------------------------------------------
    // _drawDistSpeedRow — distance (left) and speed (right)
    // -----------------------------------------------------------------------
    hidden function _drawDistSpeedRow(dc as Graphics.Dc, w as Number, mid as Number,
                                      colL as Number, colR as Number,
                                      rowTop as Number, rowBottom as Number) as Void {
        var tinyH  = dc.getFontHeight(Graphics.FONT_XTINY);
        var medH   = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var gap    = -2;
        var labelY = _centeredLabelY(rowTop, rowBottom, tinyH, medH, gap);
        var valueY = labelY + tinyH + gap;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colL, labelY, Graphics.FONT_XTINY,  "DIST (km)",  Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colR, labelY, Graphics.FONT_XTINY,  "SPD (km/h)", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colL, valueY, Graphics.FONT_MEDIUM,
            (_ble.distanceM / 1000.0f).format("%.2f"),  Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colR, valueY, Graphics.FONT_MEDIUM,
            _ble.speedKph.format("%.1f"),                Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(mid, rowTop + 1, mid, rowBottom);
    }

    // -----------------------------------------------------------------------
    // _drawPowerCadenceRow — power (left) and cadence (right)
    // -----------------------------------------------------------------------
    hidden function _drawPowerCadenceRow(dc as Graphics.Dc, w as Number, mid as Number,
                                         colL as Number, colR as Number,
                                         rowTop as Number, rowBottom as Number) as Void {
        var tinyH  = dc.getFontHeight(Graphics.FONT_XTINY);
        var medH   = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var gap    = -2;
        var labelY = _centeredLabelY(rowTop, rowBottom, tinyH, medH, gap);
        var valueY = labelY + tinyH + gap;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colL, labelY, Graphics.FONT_XTINY,  "PWR (W)",   Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colR, labelY, Graphics.FONT_XTINY,  "CAD (rpm)", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colL, valueY, Graphics.FONT_MEDIUM,
            _ble.powerW.toString(),                      Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colR, valueY, Graphics.FONT_MEDIUM,
            Math.round(_ble.cadenceRpm).toNumber().toString(), Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(mid, rowTop + 1, mid, rowBottom);
    }

    // -----------------------------------------------------------------------
    // _drawTimerRow — "TIMER ●" label + elapsed time value
    // -----------------------------------------------------------------------
    hidden function _drawTimerRow(dc as Graphics.Dc, w as Number, mid as Number,
                                  rowTop as Number, h as Number) as Void {
        var tinyH  = dc.getFontHeight(Graphics.FONT_XTINY);
        var medH   = dc.getFontHeight(Graphics.FONT_MEDIUM);
        var gap    = -2;
        var labelY = _centeredLabelY(rowTop, h, tinyH, medH, gap);
        var valueY = labelY + tinyH + gap;

        var timerLabel = "TIMER";
        var statusDot  = " \u25CF";
        var labelW = dc.getTextWidthInPixels(timerLabel, Graphics.FONT_XTINY);
        var dotW   = dc.getTextWidthInPixels(statusDot,  Graphics.FONT_XTINY);
        var startX = mid - (labelW + dotW) / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX, labelY, Graphics.FONT_XTINY, timerLabel, Graphics.TEXT_JUSTIFY_LEFT);

        var dotColor = (_ble.getState() == STATE_CONNECTED)
            ? Graphics.COLOR_GREEN : Graphics.COLOR_YELLOW;
        dc.setColor(dotColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(startX + labelW, labelY, Graphics.FONT_XTINY, statusDot, Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(mid, valueY, Graphics.FONT_MEDIUM, _formatTimer(_timerMs),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // -----------------------------------------------------------------------
    // _writeFitFields — writes BLE metrics to the FIT file
    // -----------------------------------------------------------------------
    hidden function _writeFitFields() as Void {
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

    // -----------------------------------------------------------------------
    // _formatTimer — ms → "MM:SS" or "H:MM:SS"
    // -----------------------------------------------------------------------
    hidden function _formatTimer(ms as Number) as String {
        var s   = (ms / 1000).toNumber();
        var hr  = s / 3600;
        var min = (s % 3600) / 60;
        var sec = s % 60;
        if (hr > 0) {
            return hr.format("%d") + ":" + min.format("%02d") + ":" + sec.format("%02d");
        }
        return min.format("%02d") + ":" + sec.format("%02d");
    }

}
