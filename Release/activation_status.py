#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

RUNTIME_REQUIREMENTS = {
    "FieldReport": [
        "Run project/finding/photo/PDF flows on a physical device",
        "Download a real Whisper model and transcribe recorded audio",
        "Verify share completion and free-export accounting in the system share sheet",
        "Complete and restore each StoreKit product in Sandbox",
        "Capture and review App Store screenshots from the running app",
    ],
    "BarbellLedger": [
        "Import a real FitNotes export, including same-day and incremental files",
        "Verify active-workout persistence, rest notifications, charts, and progression on device",
        "Complete and restore each StoreKit product in Sandbox",
        "Capture and review App Store screenshots from the running app",
    ],
    "DocKeeper": [
        "Scan and OCR a real multi-page document on a physical device",
        "Verify draft preview/cancel and deletion rollback without file loss",
        "Upload a PDF to a real Paperless-ngx test server",
        "Verify expiry notifications and StoreKit Sandbox purchase restoration",
        "Capture and review App Store screenshots from the running app",
    ],
}


def xcode_available():
    try:
        result = subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True, check=True)
        return "Xcode" in result.stdout
    except (OSError, subprocess.CalledProcessError):
        return False


def main():
    config = json.loads((ROOT / "Release" / "apps.json").read_text(encoding="utf-8"))
    has_xcode = xcode_available()
    apps = []
    for app in config["apps"]:
        blockers = [] if has_xcode else ["Install and select full Xcode"]
        if not app.get("app_store_url"):
            blockers.append("Create the App Store Connect app and configure its real store URL")
        if not app.get("support_url"):
            blockers.append("Host the support page with a monitored support contact and configure support_url")
        if not app.get("privacy_url"):
            blockers.append("Host the privacy policy and configure privacy_url")
        blockers.extend(f"Pending: {item}" for item in RUNTIME_REQUIREMENTS[app["name"]])
        blockers.append("Register and review all App Store Connect in-app purchase products")
        apps.append({"app": app["name"], "ready": not blockers, "blockers": blockers})
    report = {
        "ready": False,
        "external_actions_not_performed": [
            "Verification of App Store Connect agreements, tax and banking setup",
            "App Store archive upload and review submission",
            "Public landing/support/privacy page deployment",
            "Apple Ads activation and budget spending",
        ],
        "apps": apps,
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0 if all(app["ready"] for app in apps) else 2


if __name__ == "__main__":
    sys.exit(main())
