#!/bin/zsh

set -euo pipefail

project_directory=${0:A:h:h}
script_name=${0:t}
application_directory="$project_directory/.build/products/Mac Display Connect.app"
application_executable="$application_directory/Contents/MacOS/MacDisplayConnect"
cycle_count=20
vision_pro_name=""

usage() {
    print -u2 \
        "Usage: $script_name [--cycles COUNT] [--vision-pro-name NAME]"
}

require_app_not_running() {
    if pgrep -x MacDisplayConnect >/dev/null; then
        print -u2 "Quit Mac Display Connect before starting the system test."
        exit 1
    fi
}

while (( $# > 0 )); do
    case "$1" in
        --cycles)
            (( $# >= 2 )) || {
                usage
                exit 64
            }
            cycle_count=$2
            shift 2
            ;;
        --vision-pro-name)
            (( $# >= 2 )) || {
                usage
                exit 64
            }
            vision_pro_name=$2
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            print -u2 "Unknown argument: $1"
            usage
            exit 64
            ;;
    esac
done

if [[ "$cycle_count" != <1-> ]]; then
    print -u2 -- "--cycles must be a positive integer."
    exit 64
fi

require_app_not_running
"$project_directory/scripts/build-app.sh"
require_app_not_running

run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_directory="$HOME/Library/Logs/Mac Display Connect/System Tests/$run_id"
report_path="$run_directory/report.json"
application_log="$HOME/Library/Logs/Mac Display Connect/Mac Display Connect.log"
process_log="$run_directory/process.log"
run_metadata="$run_directory/run.txt"
system_log="$run_directory/system.log"
mkdir -p "$run_directory"

arguments=(
    --system-test-cycles "$cycle_count"
    --system-test-report "$report_path"
)
if [[ -n "$vision_pro_name" ]]; then
    arguments+=(--vision-pro-name "$vision_pro_name")
fi

print "Physical-device system test: $cycle_count cycle(s)"
print "Keep Apple Vision Pro worn and unlocked for the entire run."
print "Artifacts: $run_directory"

started_at=$(date "+%Y-%m-%d %H:%M:%S")
{
    print "run_id=$run_id"
    print "started_at=$started_at"
    print "cycles=$cycle_count"
    print "vision_pro_name=${vision_pro_name:-automatic}"
    print "executable=$application_executable"
} >"$run_metadata"

set +e
caffeinate -dimsu /usr/bin/open -n -W "$application_directory" \
    --args "${arguments[@]}" \
    >"$process_log" 2>&1
launcher_status=$?
set -e
print "launcher_status=$launcher_status" >>"$run_metadata"
cat "$process_log"

if [[ -f "$application_log" ]]; then
    cp "$application_log" "$run_directory/application.log"
fi

if [[ -f "$report_path" ]]; then
    passed=$(plutil -extract passed raw -o - "$report_path")
else
    passed=false
fi

if (( launcher_status != 0 )) || [[ "$passed" != "true" ]]; then
    /usr/bin/log show \
        --start "$started_at" \
        --style compact \
        --predicate \
        'process == "ControlCenter" OR process == "SidecarDisplayAgent" OR process == "SidecarRelay"' \
        >"$system_log" 2>&1 || true
fi

if [[ ! -f "$report_path" ]]; then
    print -u2 \
        "The app exited without writing a system-test report. See $process_log"
    exit 1
fi

if [[ "$passed" == "true" && $launcher_status -eq 0 ]]; then
    print "PASS: all $cycle_count cycle(s) completed."
    exit 0
fi

print -u2 "FAIL: see $report_path"
exit 1
