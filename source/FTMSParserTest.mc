// FTMSParserTest.mc — run with: monkeyc ... -t ; then connectiq + monkeydo -t
import Toybox.Test;
import Toybox.Lang;

(:test)
function testSpeedCadencePower(logger as Test.Logger) as Boolean {
    // flags 0x0044: cadence + power present, speed present (bit0 = 0)
    // speed 2840 (28.40 km/h), cadence 170 (85 rpm), power 247
    var d = [0x44, 0x00, 0x18, 0x0B, 0xAA, 0x00, 0xF7, 0x00]b;
    var r = FTMSParser.parse(d);
    return (r[:speedKph] - 28.4f).abs() < 0.01f
        && (r[:cadenceRpm] - 85.0f).abs() < 0.01f
        && r[:powerW] == 247;
}

(:test)
function testSpeedAbsentWhenMoreData(logger as Test.Logger) as Boolean {
    // bit0 set -> no speed field; cadence only
    var d = [0x05, 0x00, 0xAA, 0x00]b;
    var r = FTMSParser.parse(d);
    return r[:speedKph] == null && (r[:cadenceRpm] - 85.0f).abs() < 0.01f;
}

(:test)
function testDistance24Bit(logger as Test.Logger) as Boolean {
    // flags 0x0011: distance, bit0 set (no speed); 0x012345 = 74565 m
    var d = [0x11, 0x00, 0x45, 0x23, 0x01]b;
    return FTMSParser.parse(d)[:distanceM] == 74565;
}

(:test)
function testNegativePower(logger as Test.Logger) as Boolean {
    var d = [0x41, 0x00, 0xFF, 0xFF]b;   // power = -1
    return FTMSParser.parse(d)[:powerW] == -1;
}

(:test)
function testTruncatedPacket(logger as Test.Logger) as Boolean {
    var d = [0x44, 0x00, 0x18]b;         // speed cut short
    var r = FTMSParser.parse(d);
    return r[:speedKph] == null && r[:powerW] == null;
}
