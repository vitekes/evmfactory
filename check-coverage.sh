#!/bin/bash
set -e
THRESHOLD=${1:-90}
if [ ! -f coverage/lcov.info ]; then
  echo "coverage/lcov.info not found"
  exit 1
fi
LF=$(grep -h "^LF:" coverage/lcov.info | awk -F':' '{sum+=$2} END {print sum}')
LH=$(grep -h "^LH:" coverage/lcov.info | awk -F':' '{sum+=$2} END {print sum}')
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
