#!/usr/bin/env bash
set -euo pipefail

SRC_URL="https://services.swpc.noaa.gov/text/ace-magnetometer.txt"
TMP_FILE="$(mktemp)"
OUT_FILE="Bz.txt"

curl -fsSL "$SRC_URL" -o "$TMP_FILE"

# Exact header HamClock expects
echo "# UNIX        Bx     By     Bz     Bt" > "$OUT_FILE"

awk '
# Match only real data rows
$1 ~ /^[0-9]{4}$/ && NF >= 11 {

    year = $1
    mon  = $2
    day  = $3
    hhmm = $4

    hour = int(hhmm / 100)
    min  = hhmm % 100

    # Build UTC timestamp
    ts = sprintf("%04d-%02d-%02d %02d:%02d:00",
                 year, mon, day, hour, min)

    cmd = "date -u -d \"" ts "\" +%s"
    if ((cmd | getline epoch) <= 0) {
        close(cmd)
        next
    }
    close(cmd)

    bx = $8
    by = $9
    bz = $10
    bt = $11

    # Skip missing/bad data rows explicitly
    if (bx == -999.9 || by == -999.9 || bz == -999.9 || bt == -999.9)
        next

    printf "%-10s %6.1f %6.1f %6.1f %6.1f\n",
           epoch, bx, by, bz, bt
}
' "$TMP_FILE" >> "$OUT_FILE"

rm -f "$TMP_FILE"
