#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
XCODEGEN="$ROOT/.tools/XcodeGen/bin/xcodegen"
DESTINATION="$ROOT/DerivedData"

if ! command -v xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
    echo "Full Xcode is required. Install Xcode and select it with xcode-select before archiving." >&2
    exit 2
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <FieldReport|BarbellLedger|DocKeeper|all> [DevelopmentTeamID]" >&2
    exit 64
fi

if [[ "$1" == "all" ]]; then
    apps=(FieldReport BarbellLedger DocKeeper)
else
    apps=("$1")
fi

for app in "${apps[@]}"; do
    app_dir="$ROOT/Apps/$app"
    if [[ ! -f "$app_dir/project.yml" ]]; then
        echo "Unknown app or missing project: $app" >&2
        exit 65
    fi
    (
        cd "$app_dir"
        "$XCODEGEN" generate
        args=(
            -project "$app.xcodeproj"
            -scheme "$app"
            -configuration Release
            -destination "generic/platform=iOS"
            -archivePath "$DESTINATION/Archives/$app.xcarchive"
            -allowProvisioningUpdates
            -allowProvisioningDeviceRegistration
        )
        if [[ $# -eq 2 ]]; then
            args+=("DEVELOPMENT_TEAM=$2")
        fi
        xcodebuild "${args[@]}" clean archive
        export_args=(
            -exportArchive
            -archivePath "$DESTINATION/Archives/$app.xcarchive"
            -exportPath "$DESTINATION/Exports/$app"
            -exportOptionsPlist "$ROOT/Release/ExportOptions.plist"
        )
        if [[ $# -eq 2 ]]; then
            export_args+=(-allowProvisioningUpdates)
        fi
        xcodebuild "${export_args[@]}"
    )
done
