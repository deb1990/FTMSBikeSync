// FTMSParser.mc
// Static helper to parse FTMS Indoor Bike Data characteristic (UUID 0x2AD2).
//
// FTMS Indoor Bike Data flags (bytes 0-1, uint16 little-endian):
//   bit 0 = 0  → Instantaneous Speed present    (uint16, 0.01 km/h per LSB)
//   bit 1      → Average Speed present           (skip)
//   bit 2 = 1  → Instantaneous Cadence present  (uint16, 0.5 rpm per LSB)
//   bit 3      → Average Cadence present         (skip)
//   bit 4 = 1  → Total Distance present          (uint24, 1 m per LSB)
//   bit 5 = 1  → Resistance Level present        (sint16, skip)
//   bit 6 = 1  → Instantaneous Power present     (sint16, 1 W per LSB)
//   bit 7      → Average Power present           (skip)
//   ... higher bits skipped

import Toybox.Lang;

class FTMSParser {

    // Parse an Indoor Bike Data notification payload.
    //
    // @param data  ByteArray received from onCharacteristicChanged
    // @return      Dictionary with keys:
    //                :speedKph   (Float, km/h)  — always present (bit 0 = 0 means present)
    //                :cadenceRpm (Float, rpm)    — null if not in this packet
    //                :distanceM  (Number, m)     — null if not in this packet
    //                :powerW     (Number, W)     — null if not in this packet
    static function parse(data as ByteArray) as Dictionary {
        var result = {
            :speedKph        => 0.0f,
            :cadenceRpm      => null,
            :distanceM       => null,
            :powerW          => null,
            :resistanceLevel => null
        };

        // Need at least 2 bytes for the flags field
        if (data == null || data.size() < 2) {
            return result;
        }

        // Flags: little-endian uint16
        var flagLow  = data[0] & 0xFF;
        var flagHigh = data[1] & 0xFF;
        var flags    = flagLow | (flagHigh << 8);

        var offset = 2; // start reading fields after the 2-byte flags

        // --- Instantaneous Speed (present when bit 0 == 0) ---
        // uint16 LE, unit = 0.01 km/h per LSB
        var speedPresent = ((flags & 0x0001) == 0);
        if (speedPresent) {
            if (data.size() >= offset + 2) {
                var raw = (data[offset] & 0xFF) | ((data[offset + 1] & 0xFF) << 8);
                result[:speedKph] = raw * 0.01f;
            }
            offset += 2;
        }

        // --- Average Speed (bit 1, skip) ---
        if ((flags & 0x0002) != 0) {
            offset += 2;
        }

        // --- Instantaneous Cadence (bit 2, present when set) ---
        // uint16 LE, unit = 0.5 rpm per LSB
        if ((flags & 0x0004) != 0) {
            if (data.size() >= offset + 2) {
                var raw = (data[offset] & 0xFF) | ((data[offset + 1] & 0xFF) << 8);
                result[:cadenceRpm] = raw * 0.5f;
            }
            offset += 2;
        }

        // --- Average Cadence (bit 3, skip) ---
        if ((flags & 0x0008) != 0) {
            offset += 2;
        }

        // --- Total Distance (bit 4, present when set) ---
        // uint24 LE (3 bytes), unit = 1 m per LSB
        // Monkey C has no UINT24 format, so parse 3 individual bytes.
        if ((flags & 0x0010) != 0) {
            if (data.size() >= offset + 3) {
                var b0 = data[offset]     & 0xFF;
                var b1 = data[offset + 1] & 0xFF;
                var b2 = data[offset + 2] & 0xFF;
                result[:distanceM] = b0 | (b1 << 8) | (b2 << 16);
            }
            offset += 3;
        }

        // --- Resistance Level (bit 5, sint16) ---
        if ((flags & 0x0020) != 0) {
            if (data.size() >= offset + 2) {
                var raw = (data[offset] & 0xFF) | ((data[offset + 1] & 0xFF) << 8);
                if (raw >= 0x8000) { raw = raw - 0x10000; }
                result[:resistanceLevel] = raw;
            }
            offset += 2;
        }

        // --- Instantaneous Power (bit 6, present when set) ---
        // sint16 LE, unit = 1 W per LSB
        if ((flags & 0x0040) != 0) {
            if (data.size() >= offset + 2) {
                var raw = (data[offset] & 0xFF) | ((data[offset + 1] & 0xFF) << 8);
                // Sign-extend sint16
                if (raw >= 0x8000) {
                    raw = raw - 0x10000;
                }
                result[:powerW] = raw;
            }
            offset += 2;
        }

        return result;
    }

}
