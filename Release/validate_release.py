#!/usr/bin/env python3
import argparse
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check_app(app):
    results = []

    def add(name, passed, detail):
        results.append({"check": name, "passed": bool(passed), "detail": detail})

    app_dir = ROOT / app["path"]
    project_file = app_dir / "project.yml"
    xcode_project = app_dir / f"{app['name']}.xcodeproj"
    sources = sorted(
        path for path in app_dir.rglob("*.swift")
        if ".xcodeproj" not in path.parts and "DerivedData" not in path.parts
    )
    add("project_spec", project_file.is_file(), str(project_file.relative_to(ROOT)))
    add("generated_project", xcode_project.is_dir(), str(xcode_project.relative_to(ROOT)))
    add("swift_sources", len(sources) >= 5, f"{len(sources)} Swift files")

    source_text = "\n".join(path.read_text(encoding="utf-8") for path in sources)
    project_text = project_file.read_text(encoding="utf-8") if project_file.exists() else ""
    metadata_text = "\n".join(
        [project_text] + [path.read_text(encoding="utf-8") for path in app_dir.rglob("*.plist")]
    )
    add("bundle_id", app["bundle_id"] in project_text, app["bundle_id"])
    deployment_ok = any(
        re.search(pattern, project_text) is not None
        for pattern in (
            r"IPHONEOS_DEPLOYMENT_TARGET[^\n]*17(?:\.0)?",
            r"deploymentTarget:\s*[\"']17(?:\.0)?[\"']",
            r"deploymentTarget:\s*\n\s*iOS:\s*[\"']17(?:\.0)?[\"']",
        )
    )
    add("deployment_target", deployment_ok, "iOS 17 minimum")

    for product_id in app["product_ids"]:
        add(f"product:{product_id}", product_id in source_text, "StoreKit product reference")
    for key in app["required_usage_keys"]:
        add(f"permission:{key}", key in metadata_text and re.search(rf"{re.escape(key)}[^\n]*\S", metadata_text) is not None, "Purpose string required")

    icon = app_dir / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "Contents.json"
    if not icon.exists():
        matches = list(app_dir.rglob("AppIcon.appiconset/Contents.json"))
        icon = matches[0] if matches else icon
    add("app_icon", icon.is_file(), str(icon))

    unfinished = []
    for path in sources:
        text = path.read_text(encoding="utf-8")
        for marker in ("TODO", "FIXME", "fatalError(\"Not implemented", "simulated transcription", "fake purchase"):
            if marker.lower() in text.lower():
                unfinished.append(f"{path.relative_to(ROOT)}:{marker}")
    add("no_placeholder_markers", not unfinished, ", ".join(unfinished) or "No blocked implementation markers")

    privacy_manifests = list(app_dir.rglob("PrivacyInfo.xcprivacy"))
    privacy_text = "\n".join(path.read_text(encoding="utf-8") for path in privacy_manifests)
    for manifest in privacy_manifests:
        try:
            with manifest.open("rb") as handle:
                plistlib.load(handle)
            add("privacy_manifest_syntax", True, str(manifest.relative_to(ROOT)))
        except Exception as error:
            add("privacy_manifest_syntax", False, f"{manifest.relative_to(ROOT)}: {error}")
    if "UserDefaults" in source_text:
        add(
            "privacy_user_defaults",
            "NSPrivacyAccessedAPICategoryUserDefaults" in privacy_text and "CA92.1" in privacy_text,
            "UserDefaults requires an app-functionality privacy-manifest reason",
        )
    shared_file_keys = ("UIFileSharingEnabled", "LSSupportsOpeningDocumentsInPlace")
    sharing_enabled = any(
        re.search(rf"<key>{key}</key>\s*<true\s*/>", metadata_text) is not None
        or re.search(rf"{key}:\s*(YES|true)", metadata_text) is not None
        for key in shared_file_keys
    )
    add("no_unreviewed_file_sharing", not sharing_enabled, "Private app files must not be exposed through unreviewed device file sharing")

    return {"app": app["name"], "passed": all(item["passed"] for item in results), "checks": results}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-xcode", action="store_true")
    args = parser.parse_args()
    config = json.loads((ROOT / "Release" / "apps.json").read_text(encoding="utf-8"))
    report = {"apps": [check_app(app) for app in config["apps"]]}
    xcode_ok = False
    try:
        completed = subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True, check=True)
        xcode_ok = "Xcode" in completed.stdout
        detail = completed.stdout.strip().replace("\n", "; ")
    except (OSError, subprocess.CalledProcessError) as error:
        detail = str(error)
    report["xcode"] = {"available": xcode_ok, "required": args.require_xcode, "detail": detail}
    report["passed"] = all(app["passed"] for app in report["apps"]) and (xcode_ok or not args.require_xcode)
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
