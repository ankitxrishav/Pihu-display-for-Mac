#!/bin/bash
# Convenient alias for muscle memory to run the exact old behavior
exec "$(dirname "$0")/run.sh" --mode usb --rebuild-android "$@"
