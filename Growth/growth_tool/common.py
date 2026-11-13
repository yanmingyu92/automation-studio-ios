import csv
import hashlib
import json
import os
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG_DIR = ROOT / "config"
OUTPUT_DIR = ROOT / "Output"
CACHE_DIR = ROOT / ".cache"
GENERATED_LABEL = "Generated output from public data and local configuration; not customer evidence."


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def load_json(path):
    with Path(path).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_config(name):
    return load_json(CONFIG_DIR / name)


def _atomic_write(path, content):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".tmp-", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def write_json(path, value):
    content = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    _atomic_write(path, content)


def write_csv(path, fieldnames, rows):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".tmp-", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore", lineterminator="\n")
            writer.writeheader()
            for row in rows:
                writer.writerow({key: _csv_value(row.get(key)) for key in fieldnames})
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def _csv_value(value):
    if value is None:
        return ""
    if isinstance(value, (list, tuple)):
        return "|".join(str(item) for item in value)
    if isinstance(value, dict):
        return json.dumps(value, ensure_ascii=False, sort_keys=True)
    if isinstance(value, bool):
        return "true" if value else "false"
    return value


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def normalize_header(value):
    return re.sub(r"[^a-z0-9]+", "_", (value or "").strip().lower()).strip("_")


def parse_number(value):
    if value is None or isinstance(value, (int, float)):
        return value
    text = str(value).strip()
    if not text or text.lower() in {"na", "n/a", "null", "none", "--", "-"}:
        return None
    negative = text.startswith("(") and text.endswith(")")
    percent = text.endswith("%")
    text = text.strip("()").replace(",", "").replace("$", "").replace("€", "").replace("£", "")
    if percent:
        text = text[:-1]
    text = text.strip()
    try:
        number = float(text)
    except ValueError:
        return None
    if percent:
        number /= 100.0
    return -number if negative else number


def finite_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and value == value and abs(value) != float("inf")


def round_number(value, digits=6):
    return round(value, digits) if finite_number(value) else None


def parse_iso_date(value):
    if not value:
        return None
    text = str(value).strip()
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).date()
    except ValueError:
        pass
    for pattern in ("%Y/%m/%d", "%m/%d/%Y", "%d/%m/%Y", "%Y%m%d"):
        try:
            return datetime.strptime(text, pattern).date()
        except ValueError:
            continue
    return None
