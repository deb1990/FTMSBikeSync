// FTMSDataField.mc
// Full-screen Data Field for the Garmin Fenix 7 Pro.
//
// Displays live Power / Cadence / Speed / Distance from an FTMS indoor bike
// via BLE and records them into the FIT activity using standard field IDs
// so Garmin Connect and Strava can read them natively.
//
// Standard FIT Record field IDs (from FIT SDK profile):
//   4  = cadence          UINT8    rpm           (scale 1)
//   5  = distance         UINT32   m             (scale 100  → value * 100)
//   6  = speed            UINT16   m/s           (scale 1000 → value * 1000)
//   7  = power            UINT16   W             (scale 1)

import Toybox.WatchUi;
import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;

// FIT Record message number (from FIT SDK)
const FIT_MESG_RECORD = 20;

// Standard FIT Record field IDs
const FIT_FIELD_CADENCE  = 4;
const FIT_FIELD_DISTANCE = 5;
const FIT_FIELD_SPEED    = 6;
const FIT_FIELD_POWER    = 7;

// Fenix 7 Pro display is 260×260 pixels
const SCREEN_W = 260;
const SCREEN_H = 260;

class FTMSDataField extends WatchUi.DataField {

    // -----------------------------------------------------------------------
    // BLE delegate (owns the BLE connection and live metric values)
    // -----------------------------------------------------------------------
    var _ble as FTMSBleDelegate;

    // -----------------------------------------------------------------------
    // FIT Contributor fields (write to the activity's FIT file each interval)
    // -----------------------------------------------------------------------
    var _fitCadence  as FitContributor.Field;
    var _fitDistance as FitContributor.Field;
    var _fitSpeed    as FitContributor.Field;
    var _fitPower    as FitContributor.Field;

    // -----------------------------------------------------------------------
    // initialize — called once when the data field is first loaded
    // -----------------------------------------------------------------------
    function initialize() {
        DataField.initialize();

        // -- BLE setup -------------------------------------------------------
        _ble = new FTMSBleDelegate();

        // -- FIT Contributor fields ------------------------------------------
        // createField(name, fieldId, dataType, options)
        //
        // Speed:    stored as m/s * 1000 (uint16). We store (km/h / 3.6) * 1000.
        // Distance: stored as m * 100   (uint32). We store distanceM * 100.
        // Cadence:  stored as rpm        (uint8).  We store round(cadenceRpm).
        // Power:    stored as W          (uint16). We store powerW directly.
        //
        // Using standard FIT field IDs (not developer fields) ensures Strava
        // recognises power, cadence, speed, and distance natively.

        // createField is an instance method on DataField (self).
        // fieldId is a local developer ID (0-3); :nativeNum maps to the
        // standard FIT Record field number so Garmin Connect / Strava
        // recognise the data as native power, speed, cadence, distance.
        // There is no :scale option — scaling must be applied manually in setData().

        _fitCadence = createField(
            "cadence",
            0,
            FitContributor.DATA_TYPE_UINT8,
            { :nativeNum => FIT_FIELD_CADENCE, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "rpm" }
        );

        _fitDistance = createField(
            "distance",
            1,
            FitContributor.DATA_TYPE_UINT32,
            { :nativeNum => FIT_FIELD_DISTANCE, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "m" }
        );

        _fitSpeed = createField(
            "speed",
            2,
            FitContributor.DATA_TYPE_UINT16,
            { :nativeNum => FIT_FIELD_SPEED, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "m/s" }
        );

        _fitPower = createField(
            "power",
            3,
            FitContributor.DATA_TYPE_UINT16,
            { :nativeNum => FIT_FIELD_POWER, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W" }
        );
    }

    // -----------------------------------------------------------------------
    // compute — called each recording interval (typically every 1 s)
    // -----------------------------------------------------------------------
    function compute(info as Activity.Info) as Object or Null {
        var speedKph   = _ble.speedKph;
        var cadenceRpm = _ble.cadenceRpm;
        var distanceM  = _ble.distanceM;
        var powerW     = _ble.powerW;

        // Speed: FIT field 6 stores m/s * 1000 as uint16. Scale manually.
        var speedMs = speedKph / 3.6f;
        _fitSpeed.setData((speedMs * 1000.0f).toNumber());

        // Distance: FIT field 5 stores meters * 100 as uint32. Scale manually.
        _fitDistance.setData(distanceM * 100);

        // Cadence: round to nearest integer rpm
        var cadenceInt = Math.round(cadenceRpm).toNumber();
        if (cadenceInt < 0)   { cadenceInt = 0; }
        if (cadenceInt > 255) { cadenceInt = 255; } // uint8 clamp
        _fitCadence.setData(cadenceInt);

        // Power: watts, clamp to uint16 range
        var powerInt = powerW;
        if (powerInt < 0)     { powerInt = 0; }
        if (powerInt > 65535) { powerInt = 65535; }
        _fitPower.setData(powerInt);

        // Full-screen field — no single computed value needed
        return null;
    }

    // -----------------------------------------------------------------------
    // onUpdate — draw the 4-metric layout each display refresh
    // -----------------------------------------------------------------------
    function onUpdate(dc as Graphics.Dc) as Void {
        // Background
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();

        // ---- Snapshot current metrics from BLE delegate --------------------
        var speedKph   = _ble.speedKph;
        var cadenceRpm = _ble.cadenceRpm;
        var distanceM  = _ble.distanceM;
        var powerW     = _ble.powerW;
        var state      = _ble.getState();

        // ---- Column centres ------------------------------------------------
        var colLeft  = w / 4;       // ~65 px
        var colRight = (w * 3) / 4; // ~195 px

        // ---- Top half — Power & Cadence ------------------------------------
        // Label row
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colLeft,  30, Graphics.FONT_XTINY, "POWER",   Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colRight, 30, Graphics.FONT_XTINY, "CADENCE", Graphics.TEXT_JUSTIFY_CENTER);

        // Value row
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colLeft,  55, Graphics.FONT_NUMBER_MEDIUM,
            powerW.toString() + " W",    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colRight, 55, Graphics.FONT_NUMBER_MEDIUM,
            Math.round(cadenceRpm).toNumber().toString() + " rpm", Graphics.TEXT_JUSTIFY_CENTER);

        // ---- Divider line --------------------------------------------------
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(20, 118, w - 20, 118);

        // ---- Bottom half — Speed & Distance --------------------------------
        // Label row
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colLeft,  128, Graphics.FONT_XTINY, "SPEED",    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colRight, 128, Graphics.FONT_XTINY, "DISTANCE", Graphics.TEXT_JUSTIFY_CENTER);

        // Value row — speed in km/h (1 decimal), distance in km (2 decimal)
        var speedStr    = speedKph.format("%.1f") + " km/h";
        var distanceKm  = distanceM / 1000.0f;
        var distanceStr = distanceKm.format("%.2f") + " km";

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(colLeft,  153, Graphics.FONT_NUMBER_MEDIUM, speedStr,    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(colRight, 153, Graphics.FONT_NUMBER_MEDIUM, distanceStr, Graphics.TEXT_JUSTIFY_CENTER);

        // ---- Status indicator row ------------------------------------------
        _drawStatus(dc, w, h, state);
    }

    // -----------------------------------------------------------------------
    // _drawStatus — bottom status bar with coloured dot and text
    // -----------------------------------------------------------------------
    function _drawStatus(dc as Graphics.Dc, w as Number, h as Number, state as Number) as Void {
        var statusColor;
        var statusDot;
        var statusText;

        if (state == STATE_CONNECTED) {
            statusColor = Graphics.COLOR_GREEN;
            statusDot   = "●";
            statusText  = "Connected";
        } else if (state == STATE_RECONNECTING) {
            statusColor = Graphics.COLOR_YELLOW;
            statusDot   = "○";
            statusText  = "Reconnecting";
        } else {
            // STATE_SCANNING or STATE_CONNECTING
            statusColor = Graphics.COLOR_YELLOW;
            statusDot   = "◌";
            statusText  = "Searching...";
        }

        var cx = w / 2;
        var cy = h - 28; // ~232 px on 260-high screen

        // Draw dot glyph then label
        dc.setColor(statusColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 42, cy, Graphics.FONT_XTINY, statusDot,  Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx,      cy, Graphics.FONT_XTINY, statusText, Graphics.TEXT_JUSTIFY_LEFT);
    }

}
