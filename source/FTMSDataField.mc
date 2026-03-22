// FTMSDataField.mc
// Full-screen Data Field for the Garmin Fenix 7 Pro.
//
// Layout:
//   Row 1 (27%) — HR with zone-coloured background
//   Row 2 (23%) — Distance (left) | Speed (right)
//   Row 3 (23%) — Power (left)    | Cadence (right)
//   Row 4 (27%) — Activity Timer
//
// Developer field layout (mirrors original app structure):
//   Record : Speed (float32, nativeNum=6), Cad (uint16, nativeNum=4),
//            Pwr (sint16, nativeNum=7)
//   Session: AvgSpd (float32, nativeNum=14), AvgPwr (uint16, nativeNum=20),
//            PkPower (uint16, nativeNum=21), AvgCad (uint16, nativeNum=18),
//            Dist (float32)

import Toybox.Application;
import Toybox.WatchUi;
import Toybox.Activity;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.UserProfile;

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

    // Per-record developer fields
    var _fitSpeed;
    var _fitCadence;
    var _fitPower;
    var _fitLevel;

    // Session summary developer fields
    var _fitMach;
    var _fitAvgSpeed;
    var _fitAvgPower;
    var _fitPeakPower;
    var _fitAvgCadence;
    var _fitTotalDist;

    // Running totals for session averages
    var _sampleCount = 0;
    var _sumSpeedKph = 0.0f;
    var _sumPowerW   = 0;
    var _sumCadence  = 0.0f;
    var _peakPowerW  = 0;

    var _heartRate = 0;
    var _timerMs   = 0;
    var _mockHr    = 60;

    // -----------------------------------------------------------------------
    // initialize
    // -----------------------------------------------------------------------
    function initialize() {
        DataField.initialize();
        _ble = USE_MOCK_DATA ? new FTMSMockDelegate() : new FTMSBleDelegate();

        // --- Per-record fields ---
        _fitSpeed = createField(
            "Speed", 1, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "km/h" }
        );
        _fitCadence = createField(
            "Cad", 2, FitContributor.DATA_TYPE_UINT8,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "rpm" }
        );
        _fitPower = createField(
            "Pwr", 4, FitContributor.DATA_TYPE_SINT16,
            { :nativeNum => 7, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "w", :displayInChart => true }
        );
        _fitLevel = createField(
            "Level", 3, FitContributor.DATA_TYPE_UINT8,
            { :nativeNum => 10, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "number", :displayInChart => true }
        );

        // --- Session summary fields ---
        try {
            var strType = FitContributor.DATA_TYPE_STRING;
            _fitMach = createField(
                "Mach", 10, strType,
                { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "Name", :count => 16 }
            );
        } catch (e instanceof Lang.Exception) {
            _fitMach = null;
        }
        _fitAvgSpeed = createField(
            "AvgSpd", 11, FitContributor.DATA_TYPE_FLOAT,
            { :nativeNum => 14, :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "mph or kph" }
        );
        _fitAvgPower = createField(
            "AvgPwr", 12, FitContributor.DATA_TYPE_UINT16,
            { :nativeNum => 20, :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "w" }
        );
        _fitPeakPower = createField(
            "PkPower", 13, FitContributor.DATA_TYPE_UINT16,
            { :nativeNum => 20, :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "W" }
        );
        _fitAvgCadence = createField(
            "AvgCad", 14, FitContributor.DATA_TYPE_UINT16,
            { :nativeNum => 18, :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "rpm" }
        );
        _fitTotalDist = createField(
            "Dist", 15, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "mi or km" }
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

        // --- Per-record fields ---
        _fitSpeed.setData(speedKph);

        // Store cadence as uint8 rpm to match native field 4 format
        var cadenceInt = Math.round(cadenceRpm).toNumber();
        if (cadenceInt < 0)   { cadenceInt = 0; }
        if (cadenceInt > 255) { cadenceInt = 255; }
        _fitCadence.setData(cadenceInt);

        var powerInt = powerW;
        if (powerInt < -32768) { powerInt = -32768; }
        if (powerInt > 32767)  { powerInt = 32767; }
        _fitPower.setData(powerInt);

        var level = _ble.resistanceLevel;
        if (level < 0)   { level = 0; }
        if (level > 255) { level = 255; }
        _fitLevel.setData(level);

        // --- Running totals (only accumulate when receiving data) ---
        if (speedKph > 0.0f || powerW > 0) {
            _sampleCount++;
            _sumSpeedKph += speedKph;
            _sumPowerW   += powerW;
            _sumCadence  += cadenceRpm;
            if (powerW > _peakPowerW) { _peakPowerW = powerW; }
        }

        // --- Session summary fields ---
        if (_fitMach != null) {
            var bikeName = Application.Storage.getValue(STORAGE_KEY_DEVICE_NAME);
            _fitMach.setData((bikeName != null) ? bikeName : "Unknown");
        }
        if (_sampleCount > 0) {
            _fitAvgSpeed.setData(_sumSpeedKph / _sampleCount);
            _fitAvgPower.setData((_sumPowerW / _sampleCount).toNumber());
            _fitPeakPower.setData(_peakPowerW);
            _fitAvgCadence.setData(Math.round(_sumCadence / _sampleCount).toNumber());
        }
        if (distanceM > 0) {
            _fitTotalDist.setData(distanceM / 1000.0f);
        }

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
