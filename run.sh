#!/bin/zsh

set -euo pipefail

project_directory=${0:A:h}
application_directory="$project_directory/.build/products/Mac Display Connect.app"

pkill -x MacDisplayConnect 2>/dev/null || true
while pgrep -x MacDisplayConnect >/dev/null; do
    sleep 0.1
done

"$project_directory/scripts/build-app.sh"
open "$application_directory"
