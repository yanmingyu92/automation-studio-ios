#!/usr/bin/env python3
import html
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Release" / "Web"

PRIVACY = {
    "FieldReport": [
        "Projects, findings, photographs, recordings, transcripts, and generated reports are stored on your device unless you explicitly share them.",
        "Speech transcription runs on your device. Downloading or updating a speech model requires a network connection to the model host; this is a model download, not an upload of your recordings.",
        "Microphone and camera access is used only when you initiate recording or capture. Exported PDFs leave your device only through a destination that you choose.",
    ],
    "BarbellLedger": [
        "Exercises, routines, workouts, measurements, and training history are stored on your device. The developer does not operate a workout-data server.",
        "Imported and exported CSV files are accessed only through files or destinations that you choose. Rest-timer notifications are scheduled locally.",
        "No social profile, advertising identifier, health-data sale, or third-party analytics account is created.",
    ],
    "DocKeeper": [
        "Scanned documents, OCR text, metadata, thumbnails, and reminders are stored on your device unless you explicitly export or synchronize them.",
        "Optical character recognition runs on your device. Paperless-ngx synchronization is optional and sends selected data only to the server that you configure.",
        "Your Paperless-ngx token is stored in the device Keychain. The developer does not receive your server address, token, or documents.",
    ],
}

SUPPORT = {
    "FieldReport": [
        "Confirm microphone access in iOS Settings before recording.",
        "Keep the app open while downloading a model or transcribing. If transcription is interrupted, reopen the finding and retry.",
        "If a PDF export fails, verify that the project contains at least one finding and try the system share sheet again.",
    ],
    "BarbellLedger": [
        "Enable notifications in iOS Settings to receive rest-timer alerts while the app is backgrounded.",
        "Use CSV export before deleting the app or replacing your device. Local data is removed when the app is deleted.",
        "For FitNotes imports, export the original CSV from FitNotes and select it through the import control without changing its column headers.",
    ],
    "DocKeeper": [
        "Document scanning requires a physical device with a supported camera. File import remains available when scanning is unavailable.",
        "Enable notifications to receive warranty and renewal reminders.",
        "For Paperless-ngx, use an HTTPS server URL and an API token with only the permissions required by the integration.",
    ],
}


def page(title, body):
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>{html.escape(title)}</title>
<link rel="stylesheet" href="../styles.css">
</head>
<body><main><nav><a href="../index.html">App Studio</a></nav>{body}</main></body>
</html>
"""


def main():
    config = json.loads((ROOT / "Release" / "apps.json").read_text(encoding="utf-8"))
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "styles.css").write_text(""":root{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;line-height:1.6;color:#17202a;background:#f6f7f9}body{margin:0}main{max-width:760px;margin:auto;padding:2rem}nav{margin-bottom:2rem}a{color:#456fe5;text-underline-offset:.2em}section{background:white;border-radius:1rem;padding:1.5rem;margin:1rem 0}li{margin:.65rem 0}.notice{padding:1rem;border:1px solid #a6adb8;border-radius:.75rem}@media(prefers-color-scheme:dark){:root{color:#edf1f5;background:#111418}section{background:#1d2228}a{color:#9db7ff}}@media(max-width:600px){main{padding:1rem}}
""", encoding="utf-8")
    links = []
    for app in config["apps"]:
        name = app["name"]
        slug = name.lower()
        directory = OUTPUT / slug
        directory.mkdir(exist_ok=True)
        privacy_items = "".join(f"<li>{html.escape(item)}</li>" for item in PRIVACY[name])
        privacy_body = f"""<section><h1>{html.escape(name)} Privacy Policy</h1>
<p>{html.escape(name)} is designed to work without a developer-operated account, advertising SDK, or third-party analytics service.</p>
<ul>{privacy_items}</ul>
<h2>Purchases</h2><p>App Store purchases and subscriptions are processed by Apple. The developer receives transaction status needed to provide purchased features, not your full payment-card details.</p>
<h2>Support data</h2><p>If you contact support, information that you choose to include in that message is used only to investigate and respond to your request. Do not include private reports, health data, documents, recordings, or API tokens.</p>
<h2>Your choices</h2><p>You can revoke system permissions in iOS Settings, export supported data, and delete local data by deleting the app. Deleting the app can permanently delete local data that has not been exported.</p>
<h2>Policy updates</h2><p>Material changes will be reflected on this page before the corresponding app release.</p></section>"""
        (directory / "privacy.html").write_text(page(f"{name} Privacy", privacy_body), encoding="utf-8")
        support_items = "".join(f"<li>{html.escape(item)}</li>" for item in SUPPORT[name])
        contact_url = html.escape(config["support_contact_url"], quote=True)
        support_body = f"""<section><h1>{html.escape(name)} Support</h1>
<h2>Troubleshooting</h2><ul>{support_items}</ul>
<h2>Purchases</h2><p>Use Restore Purchases in the app with the Apple Account used for the original purchase. Subscription management and refunds are handled through your Apple Account.</p>
<h2>Contact</h2><p>Open a <a href="{contact_url}">GitHub support issue</a> and include the app version, iOS version, and steps to reproduce the problem. Do not include private reports, health data, documents, recordings, passwords, or API tokens.</p>
<h2>Terms</h2><p>The <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">Apple Standard End User License Agreement</a> applies unless a different agreement is supplied with the app.</p></section>"""
        (directory / "support.html").write_text(page(f"{name} Support", support_body), encoding="utf-8")
        links.append(f"<li><strong>{html.escape(name)}</strong>: <a href='{slug}/privacy.html'>Privacy</a> · <a href='{slug}/support.html'>Support</a></li>")
    index_body = f"<section><h1>App Studio Legal and Support</h1><p>Privacy and support information for applications in preparation. These pages do not claim that the applications are currently available on the App Store.</p><ul>{''.join(links)}</ul></section>"
    (OUTPUT / "index.html").write_text(page("App Studio", index_body).replace('href="../styles.css"', 'href="styles.css"').replace('href="../index.html"', 'href="index.html"'), encoding="utf-8")
    docs = ROOT / "docs"
    if docs.exists():
        shutil.rmtree(docs)
    shutil.copytree(OUTPUT, docs)
    print(f"Generated support site for {len(config['apps'])} apps at {OUTPUT} and {docs}")


if __name__ == "__main__":
    main()
