#!/bin/bash
# Prints every switch with its live state. No UI, no permissions beyond the ones
# the switches already need.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -x build/SwitchDeck.app/Contents/MacOS/SwitchDeck ]; then
  build/SwitchDeck.app/Contents/MacOS/SwitchDeck --dump
else
  swift run -c debug SwitchDeck --dump 2>/dev/null | grep -v '^\['
fi
