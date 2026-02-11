#!/bin/bash

# Get the year and month for a month ago
YEAR=$(date -d "last month" +%Y)
MONTH=$(date -d "last month" +%m)
TARGET_MONTH="${YEAR}${MONTH}"

OUTPUT="/opt/hamclock-backend/htdocs/ham/HamClock/solar-flux/solarflux-history.txt"
URL="https://www.spaceweather.gc.ca/solar_flux_data/daily_flux_values/fluxtable.txt"

# if the file doesn't exist, this is a fresh start so get the whole history. 
# Otherwise just get the latest values
if [ ! -e "OUTPUT" ]; then
    curl -s "$URL" | awk -v m="$MONTH" -v y="$YEAR" -v target="$TARGET_MONTH" '
        # 1. Skip lines that are empty or contain headers (starting with # or non-numeric)
        # The data lines usually start with a Julian Date (large number).
        /^[[:space:]]*[0-9]/ {
            
            # Column mapping
            # $1 = yearmonthday
            # $5 = Observed Flux
            
            year  = substr($1, 1, 4)
            month = substr($1, 5, 2)
            flux = $5
            
            # Only process if flux is a valid positive number
            if (flux > 0) {
                key = year + ((month - 1) / 12)
                sum[key] += flux
                count[key]++
            }
        }

        END {
            # Sort keys (Year-Month) naturally
            for (m in sum) {
                printf "%.2f %.2f\n", m, sum[m]/count[m]
            }
        }
    ' | sort -V >> "$OUTPUT"
else
    curl -s "$URL" | awk -v m="$MONTH" -v y="$YEAR" -v target="$TARGET_MONTH" '
        # Skip headers
        /^[a-zA-Z]/ || /^-/ { next }

        {
            # Check if the row matches our target yyyyMM
            if (substr($1, 1, 6) == target) {
                sum += $5
                count++
            }
        }

        END {
            if (count > 0) {
                # Calculate fractional year: Year + (Month - 1) / 12
                frac_year = y + ((m - 1) / 12)
                avg_flux = sum / count

                # %.2f ensures exactly two decimal places for both values
                printf "%.2f %.2f\n", frac_year, avg_flux
            }
        }
    ' >> "$OUTPUT"
fi
