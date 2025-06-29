#!/bin/bash
set -e
THRESHOLD=${1:-90}
FILE=""
if [ -f coverage/lcov.info ]; then
  FILE="coverage/lcov.info"
elif [ -f lcov.info ]; then
  FILE="lcov.info"
else
  echo "lcov.info not found" >&2
  exit 1
fi
LF=$(grep -h "^LF:" "$FILE" | awk -F':' '{sum+=$2} END {print sum}')
LH=$(grep -h "^LH:" "$FILE" | awk -F':' '{sum+=$2} END {print sum}')
if [ -z "$LF" ] || [ -z "$LH" ] || [ "$LF" -eq 0 ]; then
  echo "Unable to calculate coverage"
  exit 1
fi
COVERAGE=$(awk "BEGIN { printf(\"%d\", ($LH/$LF)*100) }")
echo "Coverage: ${COVERAGE}%"
if [ "$COVERAGE" -lt "$THRESHOLD" ]; then
  echo "Coverage below ${THRESHOLD}%"
  exit 1
fi
