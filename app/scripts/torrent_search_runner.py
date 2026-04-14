import importlib.util
import html
import json
import os
import re
import sys
import types
import urllib.parse
import urllib.request

DEFAULT_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:137.0) "
        "Gecko/20100101 Firefox/137.0"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}


def parse_size_bytes(value: str) -> int:
    if not value:
        return -1
    text = value.replace(",", "").strip()
    match = re.match(r"([0-9]*\.?[0-9]+)\s*([KMGTP]?B)", text, re.I)
    if not match:
        return -1
    num = float(match.group(1))
    unit = match.group(2).upper()
    scale = {
        "B": 1,
        "KB": 1024,
        "MB": 1024 ** 2,
        "GB": 1024 ** 3,
        "TB": 1024 ** 4,
        "PB": 1024 ** 5,
    }.get(unit, 1)
    return int(num * scale)


def retrieve_url(url, headers=None, request_data=None):
    data = request_data
    if isinstance(data, str):
        data = data.encode("utf-8")
    merged_headers = dict(DEFAULT_HEADERS)
    if headers:
        merged_headers.update(headers)
    req = urllib.request.Request(url, data=data, headers=merged_headers)
    with urllib.request.urlopen(req, timeout=20) as response:
        return response.read().decode("utf-8", errors="ignore")


def download_file(url, referer=None):
    headers = dict(DEFAULT_HEADERS)
    if referer:
        headers["Referer"] = referer
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=20) as response:
        return response.read()


def any_size_to_bytes(value):
    return parse_size_bytes(value)


results = []
issues = []
current_plugin_file = ""
current_engine_name = ""


def emit(obj):
    print(json.dumps(obj), flush=True)


def pretty_printer(row):
    item = dict(row)
    raw_link = str(item.get("link", "")).strip()
    size_text = str(item.get("size", "")).strip()
    size_bytes = parse_size_bytes(size_text)
    if size_bytes > 0 and (not size_text or re.fullmatch(r"\d+\s*B", size_text, re.I)):
        size_text = parse_size_display(size_bytes)
    payload = {
        "name": str(item.get("name", "")).strip(),
        "size": size_text,
        "sizeBytes": size_bytes,
        "seeders": int(str(item.get("seeds", "-1")).strip() or "-1") if str(item.get("seeds", "-1")).strip().lstrip("-").isdigit() else -1,
        "leechers": int(str(item.get("leech", "-1")).strip() or "-1") if str(item.get("leech", "-1")).strip().lstrip("-").isdigit() else -1,
        "engine": str(item.get("engine_name") or current_engine_name or item.get("engine_url") or "").strip(),
        "publishedOn": str(item.get("pub_date", "")).strip(),
        "pluginFile": current_plugin_file,
        "downloadLink": raw_link,
        "magnetLink": raw_link if raw_link.lower().startswith("magnet:") else "",
        "descriptionUrl": str(item.get("desc_link", "")).strip(),
    }
    results.append(payload)
    emit({"type": "result", "payload": payload})


def parse_size_display(size_bytes: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    value = float(size_bytes)
    unit_index = 0
    while value >= 1024.0 and unit_index < len(units) - 1:
        value /= 1024.0
        unit_index += 1
    precision = 0 if value >= 100 or unit_index == 0 else (1 if value >= 10 else 2)
    return f"{value:.{precision}f} {units[unit_index]}"


helpers = types.ModuleType("helpers")
helpers.retrieve_url = retrieve_url
helpers.download_file = download_file
helpers.htmlentitydecode = html.unescape
novaprinter = types.ModuleType("novaprinter")
novaprinter.prettyPrinter = pretty_printer
novaprinter.anySizeToBytes = any_size_to_bytes
sys.modules["helpers"] = helpers
sys.modules["novaprinter"] = novaprinter


def load_and_run(plugin_path, query):
    global current_plugin_file, current_engine_name
    module_name = os.path.splitext(os.path.basename(plugin_path))[0]
    spec = importlib.util.spec_from_file_location(module_name, plugin_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    plugin_class = getattr(module, module_name, None)
    if plugin_class is None:
        for value in module.__dict__.values():
            if isinstance(value, type) and hasattr(value, "search"):
                plugin_class = value
                break
    if plugin_class is None:
        return
    plugin = plugin_class()
    current_plugin_file = os.path.basename(plugin_path)
    current_engine_name = getattr(plugin, "name", module_name)
    plugin.search(query, "all")
    for item in results:
        if not item["engine"]:
            item["engine"] = current_engine_name


def resolve_download(plugin_dir, plugin_file, download_link):
    plugin_path = os.path.join(plugin_dir, plugin_file)
    module_name = os.path.splitext(os.path.basename(plugin_path))[0]
    spec = importlib.util.spec_from_file_location(module_name, plugin_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    plugin_class = getattr(module, module_name, None)
    if plugin_class is None:
        for value in module.__dict__.values():
            if isinstance(value, type) and hasattr(value, "download_torrent"):
                plugin_class = value
                break
    if plugin_class is None:
        return 1
    plugin = plugin_class()
    if hasattr(plugin, "download_torrent"):
        plugin.download_torrent(download_link)
        return 0
    print(download_link)
    return 0


def main():
    if len(sys.argv) >= 5 and sys.argv[1] == "--resolve":
        return resolve_download(sys.argv[2], sys.argv[3], sys.argv[4])
    if len(sys.argv) < 4:
        print(json.dumps({"results": [], "message": "Missing search arguments."}))
        return 1
    plugin_dir = sys.argv[1]
    query = urllib.parse.quote(sys.argv[2], safe="")
    plugin_files = sys.argv[3:]
    start_count = 0
    for file_name in plugin_files:
        plugin_path = os.path.join(plugin_dir, file_name)
        if not os.path.exists(plugin_path):
            continue
        emit({"type": "status", "message": f"Searching {start_count + 1} of {len(plugin_files)} plugins..."})
        before = len(results)
        try:
            load_and_run(plugin_path, query)
            for item in results[before:]:
                if not item["engine"]:
                    item["engine"] = os.path.splitext(file_name)[0]
        except Exception as exc:
            issues.append(f"{file_name}: {exc}")
        start_count += 1
    emit({
        "type": "summary",
        "message": f"Found {len(results)} result(s) from {start_count} plugin(s)." + (f" Issues: {'; '.join(issues[:3])}" if issues else "")
    })
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
