#!/bin/bash
set -euo pipefail
THRESHOLD=${1:-90}
FILE="coverage/lcov.info"
if [ ! -f "$FILE" ]; then
  echo "$FILE not found" >&2
  exit 1
fi
LF=$(grep -h "^LF:" "$FILE" | awk -F':' '{sum+=$2} END {print sum}')
LH=$(grep -h "^LH:" "$FILE" | awk -F':' '{sum+=$2} END {print sum}')
if [ -z "$LF" ] || [ -z "$LH" ] || [ "$LF" -eq 0 ]; then
  echo "Unable to calculate coverage" >&2
  exit 1
fi
COVERAGE=$(awk "BEGIN { printf(\"%d\", ($LH/$LF)*100) }")
echo "Coverage: ${COVERAGE}%"
if [ "$COVERAGE" -lt "$THRESHOLD" ]; then
  echo "Coverage below ${THRESHOLD}%" >&2
  exit 1
fi
