#!/usr/bin/env python3
"""
Stellar Translation Auto-Filler
===============================
Uses a local LLM (LM Studio) or DeepSeek API to fill missing translations in all .ts files.

stellar_en.ts is the master file. Its <translation> values are the authoritative
English source text. All other language files are synced against it:

  - Strings in EN but missing/empty in target          → translated and added
  - Strings in target but absent from EN               → dropped (removed strings)
  - Strings whose %N placeholders don't match EN       → re-translated
  - Existing valid translations                        → left untouched
  - --force                                            → retranslate everything

Usage:
    python fill_translations.py                          # fill ALL missing (local LLM)
    python fill_translations.py it de es                 # fill specific languages
    python fill_translations.py --backend deepseek       # use DeepSeek API (parallel, up to 200 concurrent)
    python fill_translations.py --dry-run                # show what would be translated/dropped
    python fill_translations.py --force                  # retranslate everything
    python fill_translations.py --batch 5                # batch size per LLM call
    python fill_translations.py --check                  # report issues only, no LLM calls
"""

import argparse
import json
import os
import re
import sys
import threading
import time
import urllib.request
import xml.etree.ElementTree as ET
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Set

# ── UTF-8 on Windows ─────────────────────────────────────────────────────────────
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# ── Load .env ────────────────────────────────────────────────────────────────────

def _load_dotenv():
    env_path = Path(__file__).resolve().parent / ".env"
    if not env_path.exists():
        return
    with open(env_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            val = val.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = val

_load_dotenv()

# ── Configuration ────────────────────────────────────────────────────────────────

LLM_URL         = "http://127.0.0.1:1234/v1/chat/completions"
LLM_MODEL       = "qwen/qwen3.5-9b"
LLM_TEMPERATURE = 0.1
LLM_MAX_TOKENS  = 4096
LLM_TIMEOUT     = 120
MAX_RETRIES_PER_BATCH = 1
RETRY_DELAY     = 1

DEEPSEEK_BASE_URL        = "https://api.deepseek.com"
DEEPSEEK_MODEL           = "deepseek-v4-pro"
DEEPSEEK_MAX_CONCURRENCY = 200

# Active backend — set by CLI arg in main(); "local" or "deepseek"
_BACKEND = "local"

# Thread-local OpenAI client so each thread reuses its own connection pool.
_tls = threading.local()
_progress_lock = threading.Lock()
_print_lock    = threading.Lock()

SCRIPT_DIR       = Path(__file__).resolve().parent
TRANSLATIONS_DIR = SCRIPT_DIR / "translations"
PROGRESS_FILE    = SCRIPT_DIR / ".translation_progress.json"

LANG_NAMES = {
    "sq": "Albanian", "am": "Amharic", "ar": "Arabic", "hy": "Armenian",
    "az": "Azerbaijani", "be": "Belarusian", "bn": "Bengali", "bs": "Bosnian",
    "bg": "Bulgarian", "my": "Burmese", "ca": "Catalan",
    "zh_CN": "Chinese (Simplified)", "zh_TW": "Chinese (Traditional)",
    "hr": "Croatian", "cs": "Czech", "da": "Danish", "nl": "Dutch",
    "nl_BE": "Dutch (Belgium)", "en": "English", "et": "Estonian",
    "fa": "Persian", "fi": "Finnish", "fil": "Filipino", "fr": "French",
    "gl": "Galician", "ka": "Georgian", "de": "German", "el": "Greek",
    "gu": "Gujarati", "ha": "Hausa", "he": "Hebrew", "hi": "Hindi",
    "hu": "Hungarian", "ig": "Igbo", "id": "Indonesian", "ga": "Irish",
    "it": "Italian", "ja": "Japanese", "jv": "Javanese", "kn": "Kannada",
    "km": "Khmer", "ko": "Korean", "lo": "Lao", "lv": "Latvian",
    "lt": "Lithuanian", "mk": "Macedonian", "ml": "Malayalam",
    "mr": "Marathi", "mn": "Mongolian", "ms": "Malay", "ne": "Nepali",
    "nb": "Norwegian Bokmål", "ps": "Pashto", "pl": "Polish",
    "pt": "Portuguese", "pt_BR": "Portuguese (Brazil)", "pa": "Punjabi",
    "ro": "Romanian", "ru": "Russian", "si": "Sinhala", "sk": "Slovak",
    "sl": "Slovenian", "sr_Cyrl": "Serbian (Cyrillic)", "sr_Latn": "Serbian (Latin)",
    "es": "Spanish", "sw": "Swahili", "sv": "Swedish", "ta": "Tamil",
    "te": "Telugu", "th": "Thai", "tr": "Turkish", "ug": "Uyghur",
    "uk": "Ukrainian", "ur": "Urdu", "uz": "Uzbek", "vi": "Vietnamese",
    "cy": "Welsh", "yo": "Yoruba",
}

LOCALE_MAP = {
    "sq": "sq_AL", "am": "am_ET", "ar": "ar_SA", "hy": "hy_AM",
    "az": "az_AZ", "be": "be_BY", "bn": "bn_BD", "bs": "bs_BA",
    "bg": "bg_BG", "my": "my_MM", "ca": "ca_ES",
    "zh_CN": "zh_CN", "zh_TW": "zh_TW", "hr": "hr_HR", "cs": "cs_CZ",
    "da": "da_DK", "nl": "nl_NL", "nl_BE": "nl_BE", "en": "en_US",
    "et": "et_EE", "fa": "fa_IR", "fi": "fi_FI", "fil": "fil_PH",
    "fr": "fr_FR", "gl": "gl_ES", "ka": "ka_GE", "de": "de_DE",
    "el": "el_GR", "gu": "gu_IN", "ha": "ha_NG", "he": "he_IL",
    "hi": "hi_IN", "hu": "hu_HU", "ig": "ig_NG", "id": "id_ID",
    "ga": "ga_IE", "it": "it_IT", "ja": "ja_JP", "jv": "jv_ID",
    "kn": "kn_IN", "km": "km_KH", "ko": "ko_KR", "lo": "lo_LA",
    "lv": "lv_LV", "lt": "lt_LT", "mk": "mk_MK", "ml": "ml_IN",
    "mr": "mr_IN", "mn": "mn_MN", "ms": "ms_MY", "ne": "ne_NP",
    "nb": "nb_NO", "ps": "ps_AF", "pl": "pl_PL", "pt": "pt_PT",
    "pt_BR": "pt_BR", "pa": "pa_IN", "ro": "ro_RO", "ru": "ru_RU",
    "si": "si_LK", "sk": "sk_SK", "sl": "sl_SI",
    "sr_Cyrl": "sr_RS", "sr_Latn": "sr_RS",
    "es": "es_ES", "sw": "sw_KE", "sv": "sv_SE", "ta": "ta_IN",
    "te": "te_IN", "th": "th_TH", "tr": "tr_TR", "ug": "ug_CN",
    "uk": "uk_UA", "ur": "ur_PK", "uz": "uz_UZ", "vi": "vi_VN",
    "cy": "cy_GB", "yo": "yo_NG",
}

# ── Placeholder validation ────────────────────────────────────────────────────────

_ARG_RE = re.compile(r'%(\d+|n)')

def extract_args(text: str) -> Set[str]:
    """Return set of %N / %n placeholders present in text."""
    return set(_ARG_RE.findall(text)) if text else set()

def args_match(eng: str, tr: str) -> bool:
    """True when translation contains exactly the same %N args as English source."""
    return extract_args(eng) == extract_args(tr)


# ── XML Parsing ──────────────────────────────────────────────────────────────────

def parse_ts(filepath: str) -> List[Tuple[str, str, Optional[str]]]:
    """Parse .ts into list of (context, source, translation_or_None).

    Returns None for translation when element is absent or empty.
    """
    tree = ET.parse(filepath)
    entries = []
    for ctx in tree.getroot():
        if ctx.tag != "context":
            continue
        name_el  = ctx.find("name")
        ctx_name = (name_el.text or "").strip() if name_el is not None else ""
        for msg in ctx:
            if msg.tag != "message":
                continue
            src_el = msg.find("source")
            tr_el  = msg.find("translation")
            if src_el is None or src_el.text is None:
                continue
            src = src_el.text
            tr  = None
            if tr_el is not None and tr_el.text and tr_el.text.strip():
                tr = tr_el.text
            entries.append((ctx_name, src, tr))
    return entries


def load_canonical() -> List[Tuple[str, str, str]]:
    """Load stellar_en.ts → list of (context, source_key, english_text).

    english_text = <translation> value (always equals source now that en.ts is
    fully filled, but falls back to source for safety).
    """
    en_path = TRANSLATIONS_DIR / "stellar_en.ts"
    if not en_path.exists():
        raise FileNotFoundError(f"Master English file not found: {en_path}")
    result = []
    for ctx, src, tr in parse_ts(str(en_path)):
        result.append((ctx, src, tr if tr else src))
    return result


def load_existing_translations(lang_code: str) -> Dict[Tuple[str, str], str]:
    """Return {(context, source_key): translation} for existing non-empty entries."""
    filepath = TRANSLATIONS_DIR / f"stellar_{lang_code}.ts"
    if not filepath.exists():
        return {}
    return {(ctx, src): tr for ctx, src, tr in parse_ts(str(filepath)) if tr}


# ── Writing ──────────────────────────────────────────────────────────────────────

def write_ts(lang_code: str, entries: List[Tuple[str, str, str]]):
    """Write complete .ts file from (context, source_key, translation) entries."""
    filepath = TRANSLATIONS_DIR / f"stellar_{lang_code}.ts"

    contexts: OrderedDict = OrderedDict()
    for ctx, src, tr in entries:
        contexts.setdefault(ctx, []).append((src, tr))

    locale = LOCALE_MAP.get(lang_code, f"{lang_code}_{lang_code.upper()}")

    root    = ET.Element("TS", version="2.1", language=locale, sourcelanguage="en_US")
    for ctx_name, msgs in contexts.items():
        ctx_el  = ET.SubElement(root, "context")
        name_el = ET.SubElement(ctx_el, "name")
        name_el.text = ctx_name
        for src_text, tr_text in msgs:
            msg_el = ET.SubElement(ctx_el, "message")
            src_el = ET.SubElement(msg_el, "source")
            src_el.text = src_text
            tr_el  = ET.SubElement(msg_el, "translation")
            tr_el.text = tr_text or ""

    import xml.dom.minidom as minidom
    rough  = ET.tostring(root, encoding="unicode")
    dom    = minidom.parseString(rough)
    pretty = dom.toprettyxml(indent="    ", encoding="utf-8")
    lines  = pretty.decode("utf-8").split("\n")
    if lines[0].startswith("<?xml"):
        del lines[0]
    output = '<?xml version="1.0" encoding="utf-8"?>\n' + "\n".join(lines)

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(output)


# ── LLM Interface ────────────────────────────────────────────────────────────────

def _call_local(messages) -> Optional[str]:
    body = {
        "model": LLM_MODEL,
        "messages": messages,
        "temperature": LLM_TEMPERATURE,
        "max_tokens": LLM_MAX_TOKENS,
    }
    data = json.dumps(body).encode("utf-8")
    for attempt in range(1, MAX_RETRIES_PER_BATCH + 1):
        try:
            req  = urllib.request.Request(
                LLM_URL, data=data,
                headers={"Content-Type": "application/json"})
            resp = urllib.request.urlopen(req, timeout=LLM_TIMEOUT)
            result = json.loads(resp.read())
            resp.close()
            return result["choices"][0]["message"]["content"]
        except Exception as e:
            delay = RETRY_DELAY * (2 ** (attempt - 1))
            sys.stderr.write(f"    [LLM error attempt {attempt}: {e}]\n")
            if attempt < MAX_RETRIES_PER_BATCH:
                time.sleep(delay)
    return None


def _get_deepseek_client():
    """Return a thread-local OpenAI client for DeepSeek."""
    if not hasattr(_tls, "deepseek_client"):
        try:
            from openai import OpenAI
        except ImportError:
            print("ERROR: openai package not installed. Run: pip install openai", file=sys.stderr)
            sys.exit(1)
        api_key = os.environ.get("DEEPSEEK_API_KEY", "")
        if not api_key:
            print("ERROR: DEEPSEEK_API_KEY not set. Add it to .env or environment.", file=sys.stderr)
            sys.exit(1)
        _tls.deepseek_client = OpenAI(api_key=api_key, base_url=DEEPSEEK_BASE_URL, timeout=LLM_TIMEOUT)
    return _tls.deepseek_client


def _call_deepseek(messages) -> Optional[str]:
    client = _get_deepseek_client()

    for attempt in range(1, MAX_RETRIES_PER_BATCH + 1):
        try:
            response = client.chat.completions.create(
                model=DEEPSEEK_MODEL,
                messages=messages,
                temperature=LLM_TEMPERATURE,
                max_tokens=LLM_MAX_TOKENS,
                stream=False,
                extra_body={"thinking": {"type": "disabled"}},
            )
            return response.choices[0].message.content
        except Exception as e:
            delay = RETRY_DELAY * (2 ** (attempt - 1))
            sys.stderr.write(f"    [DeepSeek error attempt {attempt}: {e}]\n")
            if attempt < MAX_RETRIES_PER_BATCH:
                time.sleep(delay)
    return None


def call_llm(messages) -> Optional[str]:
    if _BACKEND == "deepseek":
        return _call_deepseek(messages)
    return _call_local(messages)


def parse_llm_response(response_text, expected_count):
    if not response_text:
        return None
    text = response_text.strip()

    # Strategy 1: raw JSON array
    try:
        result = json.loads(text)
        if isinstance(result, list):
            return _pad_or_truncate(result, expected_count)
    except (json.JSONDecodeError, ValueError):
        pass

    # Strategy 2: markdown code-fenced JSON
    for fence in ["```json", "```"]:
        if fence in text:
            parts = text.split(fence)
            if len(parts) >= 3:
                inner = parts[1] if fence == "```" else parts[2] if len(parts) > 2 else ""
                if "```" in inner:
                    inner = inner.split("```")[0]
                try:
                    result = json.loads(inner.strip())
                    if isinstance(result, list):
                        return _pad_or_truncate(result, expected_count)
                except (json.JSONDecodeError, ValueError):
                    pass

    # Strategy 3: numbered list with quoted values
    numbered = re.findall(
        r'^\d+\.\s*["""「」「」＂＇«»](.*?)["""「」「」＂＇«»]\s*$',
        text, re.MULTILINE)
    if len(numbered) >= 1:
        return _pad_or_truncate(numbered, expected_count)

    # Strategy 4: numbered without quotes
    numbered2 = re.findall(r'^\d+\.\s*[""]?([^"]+)[""]?\s*$', text, re.MULTILINE)
    if len(numbered2) >= expected_count * 0.5:
        cleaned = [s.strip().strip('"').strip() for s in numbered2]
        return _pad_or_truncate(cleaned, expected_count)

    # Strategy 5: plain newline separation
    lines = [l.strip() for l in text.split("\n")
             if l.strip() and not l.strip().startswith("```")]
    cleaned = []
    for line in lines:
        m = re.match(r'^\d+\.\s*(.*)', line)
        if m:
            cleaned.append(m.group(1).strip().strip('"').strip())
    if len(cleaned) >= expected_count * 0.5:
        return _pad_or_truncate(cleaned, expected_count)

    # Strategy 6: pipe-delimited
    piped = re.findall(r'\|([^|]+)\|', text)
    if len(piped) >= expected_count * 0.5:
        return _pad_or_truncate(piped, expected_count)

    return None


# Leading list artefacts a model may prepend to a value: "1. ", "2) ", "3 - ",
# "- ", "• ". Defensive net so a stray index never reaches the .ts file even if
# the model ignores the prompt rule.
_LIST_PREFIX_RE = re.compile(r'^\s*(?:\d+\s*[.)\]:\-–]\s*|[-–•*]\s+)')

def _strip_list_prefix(s: str) -> str:
    if not isinstance(s, str):
        return s
    return _LIST_PREFIX_RE.sub("", s, count=1).strip()


def _pad_or_truncate(items, target):
    result = [_strip_list_prefix(x) for x in items[:target]]
    while len(result) < target:
        result.append("")
    return result


def translate_batch(lang_name: str, sources: List[str]) -> List[str]:
    """Translate a batch of English strings into lang_name via LLM."""
    if not sources:
        return []

    # Send sources as a JSON array, NOT a numbered list. A numbered input list
    # caused weaker models to echo the "1." / "2." prefixes back inside the
    # translated strings (e.g. "5. Ajouter URL" appearing on toolbar buttons).
    sources_json = json.dumps(sources, ensure_ascii=False)

    system_prompt = (
        f"You are a professional localisation translator. "
        f"Translate these {len(sources)} English UI strings to {lang_name}.\n"
        f"CRITICAL RULES:\n"
        f"- Preserve EXACTLY: %1, %2, %n, \\n, emoji "
        f"(🟦 🟩 🔴 🟨 🟧 📄 📡 🌐 ⚠ 🛡 🛑 🔍 🔒), \U0001f6e1.\n"
        f"- Keep UNTRANSLATED: yt-dlp, ffmpeg, BitTorrent, TCP, μTP, DHT, VPN, "
        f"RSS, URL, IP, SOCKS5, HTTP, HTTPS, JS, Stellar, YouTube, Windows, "
        f"macOS, Linux, Deno, Node.js, Bun, QuickJS, GNU GPL.\n"
        f"- UI strings must be CONCISE. Column headers, labels, and button text must be "
        f"short — prefer abbreviations or symbols over long noun phrases. "
        f"For example: use '↓' for download speed, '↑' for upload speed, "
        f"'Taille' not 'Taille du fichier', 'Ratio' not 'Rapport de partage'. "
        f"If the English source is 1-2 words, the translation must also be 1-2 words max.\n"
        f"- Do NOT add list numbers, bullets, indices, or any prefix to a "
        f"translation. Never output text like \"1. \", \"2) \", \"- \" in front of "
        f"a value. Translate ONLY the words, nothing else.\n"
        f"- The output array must have exactly {len(sources)} items in the same "
        f"order as the input.\n"
        f"- Return ONLY a JSON array: [\"trans1\", \"trans2\", ...]\n"
        f"- No markdown, no explanations, no code fences."
    )

    user_msg = (
        f"Input is a JSON array of {len(sources)} English strings:\n"
        f"{sources_json}\n\n"
        f"Return JSON array of {len(sources)} {lang_name} translations:"
    )

    for attempt in range(1, MAX_RETRIES_PER_BATCH + 1):
        response = call_llm([
            {"role": "system", "content": system_prompt},
            {"role": "user",   "content": user_msg},
        ])

        if response is None:
            sys.stderr.write(f"    [Batch LLM failed (no response), attempt {attempt}]\n")
            continue

        translations = parse_llm_response(response, len(sources))
        if translations is not None and any(t.strip() for t in translations):
            return translations

        sys.stderr.write(
            f"    [Batch parse failed, attempt {attempt}. Raw: {response[:100]}...]\n")

    # Last resort: one-by-one
    sys.stderr.write(
        f"    [Batch failed after {MAX_RETRIES_PER_BATCH} attempts, trying individual...]\n")
    results = []
    for src in sources:
        time.sleep(0.0)
        resp = call_llm([
            {"role": "system", "content":
             f"Translate this English UI string to {lang_name}. "
             f"Return ONLY the translation, nothing else."},
            {"role": "user", "content": src},
        ])
        if resp:
            t = resp.strip().strip('"').strip("'").strip()
            for prefix in [f"{lang_name}: ", "Translation: ", "翻訳:", "Übersetzung:"]:
                if t.startswith(prefix):
                    t = t[len(prefix):]
            results.append(t if t else "")
        else:
            results.append("")
    return results


# ── Thread-safe print ────────────────────────────────────────────────────────────

def tprint(*args, **kwargs):
    with _print_lock:
        print(*args, **kwargs)


# ── Core: sync logic ─────────────────────────────────────────────────────────────

def classify_entries(
    canonical: List[Tuple[str, str, str]],
    existing: Dict[Tuple[str, str], str],
    force: bool,
) -> Tuple[
    List[Tuple[int, str, str, str]],   # need_translation: (idx, ctx, src, eng)
    List[Tuple[str, str, str]],        # orphaned: (ctx, src, tr) — in target, not in EN
    List[Tuple[str, str, str, str]],   # arg_broken: (ctx, src, eng, bad_tr)
]:
    """Classify all entries into three buckets.

    need_translation: missing, empty, forced, or arg-broken entries to (re)translate.
    orphaned:         entries in the target file with no matching key in canonical.
    arg_broken:       existing translations with wrong %N placeholders (reported only;
                      also added to need_translation so they get re-translated).
    """
    canonical_keys: Set[Tuple[str, str]] = {(ctx, src) for ctx, src, _ in canonical}

    # Orphaned: in target but not in canonical
    orphaned = [
        (ctx, src, tr)
        for (ctx, src), tr in existing.items()
        if (ctx, src) not in canonical_keys
    ]

    need_translation = []
    arg_broken       = []

    for i, (ctx, src, eng) in enumerate(canonical):
        key    = (ctx, src)
        cur_tr = existing.get(key, "")

        if force:
            need_translation.append((i, ctx, src, eng))
            continue

        if not cur_tr.strip():
            # Missing or empty
            need_translation.append((i, ctx, src, eng))
            continue

        # Check %N placeholder consistency
        if not args_match(eng, cur_tr):
            arg_broken.append((ctx, src, eng, cur_tr))
            need_translation.append((i, ctx, src, eng))
            continue

    return need_translation, orphaned, arg_broken


def process_language(
    lang_code: str,
    canonical: List[Tuple[str, str, str]],
    dry_run: bool  = False,
    force: bool    = False,
    batch_size: int = 10,
    check_only: bool = False,
    retry_keys: List[str] = None,
) -> List[str]:
    lang_name = LANG_NAMES.get(lang_code, f"Unknown ({lang_code})")
    pfx = f"[{lang_code}]"
    tprint(f"\n{'─' * 60}")
    tprint(f"  {lang_name} ({lang_code})")
    tprint(f"{'─' * 60}")

    existing = load_existing_translations(lang_code)

    # Force-retry previously failed keys even if they appear translated in the file.
    # retry_keys are English source strings that failed in a prior run.
    retry_set: Set[str] = set(retry_keys) if retry_keys else set()
    if retry_set:
        # Temporarily remove them from existing so classify_entries re-queues them.
        for key in list(existing.keys()):
            if key[1] in retry_set:
                del existing[key]
        tprint(f"  {pfx} Retrying {len(retry_set)} previously failed string(s).")

    need_translation, orphaned, arg_broken = classify_entries(
        canonical, existing, force)

    total_canonical = len(canonical)
    tprint(f"  {pfx} Canonical strings : {total_canonical}")
    tprint(f"  {pfx} Already translated: {total_canonical - len(need_translation)}")
    tprint(f"  {pfx} Need translation  : {len(need_translation)}")
    if orphaned:
        tprint(f"  {pfx} Orphaned (removed): {len(orphaned)}")
        for ctx, src, _ in orphaned[:5]:
            tprint(f"    {pfx} [{ctx}] {src[:70]}")
        if len(orphaned) > 5:
            tprint(f"    {pfx} ... and {len(orphaned) - 5} more")
    if arg_broken:
        tprint(f"  {pfx} Arg mismatch      : {len(arg_broken)}")
        for ctx, src, eng, bad in arg_broken[:5]:
            tprint(f"    {pfx} [{ctx}] EN={extract_args(eng)} TR={extract_args(bad)}")
            tprint(f"      src: {src[:60]}")
            tprint(f"      bad: {bad[:60]}")
        if len(arg_broken) > 5:
            tprint(f"    {pfx} ... and {len(arg_broken) - 5} more")

    if check_only or dry_run:
        if dry_run and need_translation:
            tprint(f"\n  {pfx} [DRY RUN] Would translate:")
            for _, ctx, src, eng in need_translation[:20]:
                tprint(f"    [{ctx}] {eng[:80]}")
            if len(need_translation) > 20:
                tprint(f"    {pfx} ... and {len(need_translation) - 20} more")
        if orphaned and not check_only:
            tprint(f"  {pfx} [DRY RUN] Would drop {len(orphaned)} orphaned entries")
        return []

    if not need_translation and not orphaned:
        tprint(f"  {pfx} Nothing to do.")
        return []

    # Translate missing/broken entries in batches
    new_translations: Dict[Tuple[str, str], str] = {}

    english_texts = [eng for _, _, _, eng in need_translation]
    keys          = [(ctx, src) for _, ctx, src, _ in need_translation]

    total_batches = (len(english_texts) + batch_size - 1) // batch_size
    ok_total      = 0
    failed_srcs: List[str] = []  # English source strings that failed translation

    for batch_num in range(total_batches):
        start      = batch_num * batch_size
        end        = min(start + batch_size, len(english_texts))
        batch_eng  = english_texts[start:end]
        batch_keys = keys[start:end]

        tprint(f"\n  {pfx} Batch {batch_num+1}/{total_batches} ({len(batch_eng)} strings)...")
        results = translate_batch(lang_name, batch_eng)

        ok = 0
        for j, result in enumerate(results):
            ctx, src = batch_keys[j]
            eng      = batch_eng[j]
            if result and result.strip():
                # Validate args; warn but keep if broken (LLM did its best)
                if not args_match(eng, result):
                    tprint(f"    {pfx} WARN arg mismatch after translate: {extract_args(eng)} "
                           f"vs {extract_args(result)}")
                    tprint(f"      src: {eng[:60]}")
                    tprint(f"      tr : {result[:60]}")
                new_translations[(ctx, src)] = result
                ok += 1
                if j < 2:
                    tprint(f"    {pfx} OK:  {eng[:50]} -> {result[:50]}")
            else:
                tprint(f"    {pfx} FAIL: {eng[:80]}")
                failed_srcs.append(eng)

        # Items in batch_eng beyond len(results) also failed (LLM returned short array)
        for j in range(len(results), len(batch_eng)):
            eng = batch_eng[j]
            tprint(f"    {pfx} FAIL (no result): {eng[:80]}")
            failed_srcs.append(eng)

        tprint(f"    {pfx} {ok}/{len(batch_eng)} OK")
        ok_total += ok

        # Merge and write after every batch so progress survives interruption
        _merge_and_write(lang_code, canonical, existing, new_translations)

    failed_count = len(failed_srcs)
    tprint(f"\n  {pfx} Summary: {ok_total} translated, {failed_count} failed, "
           f"{len(orphaned)} orphaned entries dropped")
    if failed_srcs:
        tprint(f"  {pfx} Failed strings will be retried on next run.")

    return failed_srcs


def _merge_and_write(
    lang_code: str,
    canonical: List[Tuple[str, str, str]],
    existing: Dict[Tuple[str, str], str],
    new_translations: Dict[Tuple[str, str], str],
):
    """Merge existing + new translations; write only canonical keys (drops orphans)."""
    entries = []
    for ctx, src, _eng in canonical:
        key = (ctx, src)
        tr  = new_translations.get(key) or existing.get(key) or ""
        entries.append((ctx, src, tr))
    write_ts(lang_code, entries)


# ── Progress Tracking ────────────────────────────────────────────────────────────

def load_progress() -> tuple:
    """Return (completed_langs: set, failed_keys: dict[lang_code, list[str]])."""
    if PROGRESS_FILE.exists():
        try:
            with open(PROGRESS_FILE, "r") as f:
                data = json.load(f)
            completed = set(data.get("completed", []))
            failed    = data.get("failed_keys", {})
            return completed, failed
        except Exception:
            pass
    return set(), {}


def save_progress(completed: set, failed_keys: dict):
    PROGRESS_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(PROGRESS_FILE, "w") as f:
        json.dump({"completed": sorted(completed), "failed_keys": failed_keys}, f, indent=2)


# ── CLI ──────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Sync and auto-fill Stellar translations from stellar_en.ts master"
    )
    parser.add_argument("languages", nargs="*",
                        help="Language codes. Default: all non-EN languages.")
    parser.add_argument("--dry-run",    action="store_true",
                        help="Show what would change without calling LLM.")
    parser.add_argument("--check",      action="store_true",
                        help="Report orphans and arg mismatches only; no LLM calls.")
    parser.add_argument("--force",      action="store_true",
                        help="Retranslate all strings, ignoring existing translations.")
    parser.add_argument("--batch",      type=int, default=10,
                        help="Strings per LLM call (default: 10).")
    parser.add_argument("--dir",        type=str, default=None,
                        help="Override translations directory.")
    parser.add_argument("--all",        action="store_true",
                        help="Create and fill every language in LANG_NAMES, skipping 'en' and already-complete languages.")
    parser.add_argument("--backend",    type=str, default="local", choices=["local", "deepseek"],
                        help="LLM backend: 'local' (LM Studio, default) or 'deepseek' (DeepSeek API).")
    args = parser.parse_args()

    global TRANSLATIONS_DIR, _BACKEND
    _BACKEND = args.backend

    if args.dir:
        TRANSLATIONS_DIR = Path(args.dir)
    TRANSLATIONS_DIR = TRANSLATIONS_DIR.resolve()

    tprint(f"Dir:     {TRANSLATIONS_DIR}")
    if not (args.dry_run or args.check):
        if _BACKEND == "deepseek":
            tprint(f"Backend: DeepSeek API ({DEEPSEEK_MODEL}, up to {DEEPSEEK_MAX_CONCURRENCY} parallel languages)")
        else:
            tprint(f"Backend: Local LLM ({LLM_MODEL})")
            tprint(f"LLM URL: {LLM_URL}")
        tprint(f"Batch:   {args.batch} strings/call")

    canonical = load_canonical()
    tprint(f"Canonical (EN) strings: {len(canonical)}")

    all_ts    = sorted(TRANSLATIONS_DIR.glob("stellar_*.ts"))
    all_codes = [f.stem.replace("stellar_", "") for f in all_ts]

    if args.all:
        target = []
        for c in sorted(LANG_NAMES.keys()):
            if c == "en":
                continue
            if c not in all_codes:
                _merge_and_write(c, canonical, {}, {})
                all_codes.append(c)
                tprint(f"  Created new file: stellar_{c}.ts")
            target.append(c)
    elif args.languages:
        target = []
        for c in args.languages:
            if c == "en":
                tprint("Skipping 'en' — it is the master file.")
                continue
            if c in all_codes:
                target.append(c)
            elif c in LANG_NAMES:
                _merge_and_write(c, canonical, {}, {})
                all_codes.append(c)
                target.append(c)
                tprint(f"  Created new file: stellar_{c}.ts")
            else:
                tprint(f"  Unknown language code: {c}")
    else:
        target = [c for c in all_codes if c != "en"]

    tprint(f"Available languages: {len(all_codes)}")
    tprint(f"Will process {len(target)}: {target}\n")

    if not target:
        tprint("Nothing to do!")
        return

    if not (args.dry_run or args.check):
        if _BACKEND == "local":
            tprint("Checking LLM connectivity...")
            try:
                urllib.request.urlopen("http://127.0.0.1:1234/v1/models", timeout=5)
                tprint("LLM reachable.\n")
            except Exception:
                tprint("ERROR: LLM not reachable at http://127.0.0.1:1234", file=sys.stderr)
                sys.exit(1)
        else:
            if not os.environ.get("DEEPSEEK_API_KEY"):
                tprint("ERROR: DEEPSEEK_API_KEY not set. Add it to .env or environment.", file=sys.stderr)
                sys.exit(1)
            tprint("DeepSeek API key loaded.\n")

    completed_set, all_failed_keys = load_progress()

    def _run_one(lang_code: str):
        retry_keys  = all_failed_keys.get(lang_code, [])
        failed_srcs = process_language(
            lang_code, canonical,
            dry_run=args.dry_run,
            force=args.force,
            batch_size=args.batch,
            check_only=args.check,
            retry_keys=retry_keys,
        )
        return lang_code, failed_srcs

    # Parallel only for DeepSeek (remote API can handle concurrent requests).
    # Local LLM is a single server — run sequentially to avoid overwhelming it.
    use_parallel = (_BACKEND == "deepseek") and not (args.dry_run or args.check)
    max_workers  = min(DEEPSEEK_MAX_CONCURRENCY, len(target)) if use_parallel else 1

    if use_parallel:
        tprint(f"Running {len(target)} languages in parallel (up to {max_workers} workers)...\n")

    try:
        if max_workers == 1:
            results_iter = (_run_one(c) for c in target)
        else:
            executor = ThreadPoolExecutor(max_workers=max_workers)
            futures  = {executor.submit(_run_one, c): c for c in target}

            def results_iter():
                try:
                    for fut in as_completed(futures):
                        yield fut.result()
                finally:
                    executor.shutdown(wait=False)

            results_iter = results_iter()

        for lang_code, failed_srcs in results_iter:
            if not (args.dry_run or args.check):
                with _progress_lock:
                    if failed_srcs:
                        all_failed_keys[lang_code] = failed_srcs
                    else:
                        all_failed_keys.pop(lang_code, None)
                        completed_set.add(lang_code)
                    save_progress(completed_set, all_failed_keys)
                status = f"{len(failed_srcs)} failed" if failed_srcs else "complete"
                tprint(f"  ✓ Progress saved. ({lang_code}: {status})")

    except KeyboardInterrupt:
        tprint(f"\n⏸  Interrupted. Progress saved. Run again to resume.")
        with _progress_lock:
            save_progress(completed_set, all_failed_keys)
        sys.exit(0)

    tprint(f"\n{'=' * 60}")
    tprint(f"Done! {len(completed_set)}/{len(all_codes)} languages complete.")
    tprint(f"{'=' * 60}")


if __name__ == "__main__":
    main()
