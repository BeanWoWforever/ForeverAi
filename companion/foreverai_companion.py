"""
ForeverAi Companion - the live brain behind the in-game ForeverAi window.

How it works:
  ForeverAi (the WoW addon) shows your question and character info as a small strip of colored squares in the
  corner of its window for a few seconds. This program reads only that strip from the WoW window, asks Google
  Gemini, and draws the answer over ForeverAi's answer panel. It never sends keypresses or touches the game.

Privacy:
  - Only the ForeverAi strip is decoded; nothing else on screen is stored or sent.
  - Your Gemini key is stored only on this PC (%APPDATA%\\ForeverAi\\config.json) and only sent to Google.
  - Questions and answers are kept locally in %APPDATA%\\ForeverAi\\chats.jsonl.

Standard library only. Windows only. Normally started by ForeverAiCompanion.exe (see app.py).
"""
import ctypes
import ctypes.wintypes as w
import json
import math
import os
import random
import re
import sys
import threading
import time
import urllib.error
import urllib.request

APP_DIR = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), "ForeverAi")
CONFIG = os.path.join(APP_DIR, "config.json")
STOP_FLAG = os.path.join(APP_DIR, "stop.flag")
LOG = os.path.join(APP_DIR, "companion.log")
HERE = os.path.dirname(sys.executable if getattr(sys, "frozen", False) else os.path.abspath(__file__))


def find_addon_dir(cfg=None):
    """The installed ForeverAi addon folder (for its knowledge files). Remembered in config once found."""
    cands = []
    if cfg and cfg.get("addon_dir"):
        cands.append(cfg["addon_dir"])
    cands.append(os.path.normpath(os.path.join(HERE, "..")))  # running from inside the addon folder (dev setup)
    for drive in "CDEFG":
        for base in (r"Program Files (x86)", r"Program Files", r"Games", r""):
            cands.append(os.path.join(f"{drive}:\\", base, "World of Warcraft", "_forever_", "Interface", "AddOns", "ForeverAi"))
    for c in cands:
        if c and os.path.exists(os.path.join(c, "Knowledge", "KB.lua")):
            return c
    return None


KNOWLEDGE = os.path.join(find_addon_dir() or os.path.join(HERE, ".."), "Knowledge")
CHATLOG = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "Logs", "WoWChatLog.txt"))

Q_TAG, A_TAG = "FAIQ1~", "FAIA1~"
NEWLINE = " §§ "
API = "https://generativelanguage.googleapis.com/v1beta"


def log(msg):
    os.makedirs(APP_DIR, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")


# --------------------------------------------------------------------------- clipboard (Win32)
user32 = ctypes.WinDLL("user32", use_last_error=True) if os.name == "nt" else None
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True) if os.name == "nt" else None
CF_UNICODETEXT, GMEM_MOVEABLE = 13, 0x0002
if user32:
    user32.GetClipboardSequenceNumber.restype = w.DWORD
    user32.OpenClipboard.argtypes = [w.HWND]; user32.OpenClipboard.restype = w.BOOL
    user32.CloseClipboard.restype = w.BOOL
    user32.EmptyClipboard.restype = w.BOOL
    user32.GetClipboardData.argtypes = [w.UINT]; user32.GetClipboardData.restype = w.HANDLE
    user32.SetClipboardData.argtypes = [w.UINT, w.HANDLE]; user32.SetClipboardData.restype = w.HANDLE
    user32.RegisterClipboardFormatW.argtypes = [w.LPCWSTR]; user32.RegisterClipboardFormatW.restype = w.UINT
    user32.IsClipboardFormatAvailable.argtypes = [w.UINT]; user32.IsClipboardFormatAvailable.restype = w.BOOL
    kernel32.GlobalAlloc.argtypes = [w.UINT, ctypes.c_size_t]; kernel32.GlobalAlloc.restype = w.HGLOBAL
    kernel32.GlobalLock.argtypes = [w.HGLOBAL]; kernel32.GlobalLock.restype = w.LPVOID
    kernel32.GlobalUnlock.argtypes = [w.HGLOBAL]; kernel32.GlobalUnlock.restype = w.BOOL
    kernel32.CreateMutexW.argtypes = [w.LPVOID, w.BOOL, w.LPCWSTR]; kernel32.CreateMutexW.restype = w.HANDLE


def _open():
    for _ in range(20):
        if user32.OpenClipboard(None):
            return True
        time.sleep(0.03)
    return False


def clip_seq():
    return user32.GetClipboardSequenceNumber()


def clip_read():
    if not user32.IsClipboardFormatAvailable(CF_UNICODETEXT) or not _open():
        return None
    try:
        h = user32.GetClipboardData(CF_UNICODETEXT)
        if not h:
            return None
        p = kernel32.GlobalLock(h)
        if not p:
            return None
        try:
            return ctypes.wstring_at(p)
        finally:
            kernel32.GlobalUnlock(h)
    finally:
        user32.CloseClipboard()


def _alloc(data: bytes):
    h = kernel32.GlobalAlloc(GMEM_MOVEABLE, max(len(data), 1))
    p = kernel32.GlobalLock(h)
    ctypes.memmove(p, data, len(data))
    kernel32.GlobalUnlock(h)
    return h


def clip_write(text, private=True):
    if not _open():
        return False
    try:
        user32.EmptyClipboard()
        user32.SetClipboardData(CF_UNICODETEXT, _alloc((text + "\0").encode("utf-16-le")))
        if private:  # keep ForeverAi traffic out of Win+V history and cloud clipboard
            zero = (0).to_bytes(4, "little")
            for name, data in (("CanIncludeInClipboardHistory", zero), ("CanUploadToCloudClipboard", zero),
                               ("ExcludeClipboardContentFromMonitorProcessing", b"\0")):
                fmt = user32.RegisterClipboardFormatW(name)
                if fmt:
                    user32.SetClipboardData(fmt, _alloc(data))
        return True
    finally:
        user32.CloseClipboard()


def ding():
    try:
        import winsound
        winsound.PlaySound("SystemAsterisk", winsound.SND_ALIAS | winsound.SND_ASYNC)
    except Exception:
        pass


# --------------------------------------------------------------------------- knowledge (reads the addon's own files)
STR = r'"((?:[^"\\]|\\.)*)"'
STOP = set("""a an the is are am be to of in on at for and or i im me my it its this that do does did can could should would
will what whats how which who where when why with from about any some get got there their they them you your u ur pls
please hey yo just really very way thing things have has had like need want go going into out up down tell know much many
more most than then so if as by wow forever classic game asap lol""".split())


def unlua(s):
    return s.replace("\\n", "\n").replace('\\"', '"').replace("||", "|").replace("\\\\", "\\")


SYN = {"herb": "herbalism", "herbs": "herbalism", "herbing": "herbalism", "mine": "mining", "ore": "mining",
       "money": "gold", "cash": "gold", "ench": "enchanting", "alch": "alchemy", "bs": "blacksmithing", "lw": "leatherworking",
       "engi": "engineering", "pally": "paladin", "lock": "warlock", "hunt": "hunter", "sham": "shaman", "rep": "reputation",
       "ony": "onyxia", "mc": "molten core", "brd": "blackrock depths", "ubrs": "upper blackrock spire", "lbrs": "lower blackrock spire",
       "sm": "scarlet monastery", "zf": "zul farrak", "stv": "stranglethorn", "epl": "eastern plaguelands", "wpl": "western plaguelands"}


def toks(s):
    out = []
    for t in re.findall(r"[a-z0-9']+", s.lower().replace("'", "")):
        t = SYN.get(t, t)
        if t in STOP:
            continue
        if len(t) > 4 and t.endswith("s") and not t.endswith("ss"):
            t = t[:-1]
        out.append(t)
    return out


class Knowledge:
    def __init__(self):
        KNOWLEDGE = os.path.join(find_addon_dir(load_cfg()) or os.path.join(HERE, ".."), "Knowledge")
        log(f"knowledge folder: {KNOWLEDGE}")
        self.docs = []  # (title, text, tokens)
        for fn in ("KB.lua", "KB_Forever.lua", "KB_Fixes.lua"):
            path = os.path.join(KNOWLEDGE, fn)
            if not os.path.exists(path):
                continue
            src = open(path, encoding="utf-8").read()
            for m in re.finditer(r"add\{\s*(?:class\s*=\s*\"\w+\",\s*)?q\s*=\s*\{(.*?)\},\s*a\s*=\s*" + STR, src, re.S):
                qs = [unlua(x) for x in re.findall(STR, m.group(1))]
                a = unlua(m.group(2))
                self.docs.append((qs[0] if qs else "", a, toks(" ".join(qs) + " " + a)))
        qpath = os.path.join(KNOWLEDGE, "ForeverQuests.lua")
        if os.path.exists(qpath):
            for m in re.finditer(r"Q\[(\d+)\] = \{ t = " + STR + r", l = (\d+), m = (\d+), z = (-?\d+), o = " + STR + r"(?:, d = " + STR + r")?",
                                 open(qpath, encoding="utf-8").read()):
                title, lvl, obj = unlua(m.group(2)), m.group(3), unlua(m.group(6))
                text = f"Quest '{title}' (level {lvl}). Objective: {obj}"
                self.docs.append(("quest " + title, text, toks(title + " " + title + " " + obj)))
        for fn, label in (("Dungeons.lua", "Dungeon"), ("Zones.lua", "Zone")):
            path = os.path.join(KNOWLEDGE, fn)
            if os.path.exists(path):
                for m in re.finditer(r"\{ (?:forever = true, )?n = " + STR + r"(.*?)\},?\n", open(path, encoding="utf-8").read(), re.S):
                    body = re.sub(r"\s+", " ", m.group(2))
                    text = f"{label}: {unlua(m.group(1))} {body}"
                    self.docs.append((m.group(1), text, toks(m.group(1) + " " + m.group(1) + " " + body)))
        # BM25 stats
        self.df, self.N = {}, len(self.docs)
        self.avgdl = sum(len(d[2]) for d in self.docs) / max(1, self.N)
        for d in self.docs:
            for t in set(d[2]):
                self.df[t] = self.df.get(t, 0) + 1
        log(f"knowledge loaded: {self.N} entries")

    def search(self, query, k=8):
        q = toks(query)
        scores = []
        for i, (_, _, dt) in enumerate(self.docs):
            if not dt:
                continue
            tf = {}
            for t in dt:
                tf[t] = tf.get(t, 0) + 1
            s = 0.0
            for t in set(q):
                if t in tf:
                    idf = math.log(1 + (self.N - self.df[t] + 0.5) / (self.df[t] + 0.5))
                    f = tf[t]
                    s += idf * f * 2.2 / (f + 1.2 * (0.25 + 0.75 * len(dt) / self.avgdl))
            if s > 0:
                scores.append((s, i))
        scores.sort(reverse=True)
        return [self.docs[i] for _, i in scores[:k]]


# --------------------------------------------------------------------------- Gemini
SYSTEM = """You are ForeverAi, a friendly, sharp in-game assistant living inside the chat window of World of Warcraft: Forever
(Blizzard's "Classic+": the Vanilla world with 1,000+ new quests, new zones like Mount Hyjal, Riverglades and Zephras Isle,
new dungeons, the Skyborne race, Camping, Legacy, Merchant's Favor and reworked classes/professions; launched Nov 2026).

How to answer:
- Talk like a knowledgeable friend who plays the game. Answer the actual question directly, first line first,
  then give the useful detail: usually 4-8 short lines or numbered points with specific places, numbers and why.
- Never give a one-sentence brush-off to a broad question; a good answer here is complete enough to act on.
- Use the REFERENCE NOTES (researched Forever facts) and the PLAYER info. Personalize to their level, class and professions.
- Only mention where the player currently is when it matters for the answer (e.g. directions), and then by zone name only.
- If notes and your general Classic knowledge disagree, trust the notes: Forever changed a lot.
- PLAYER info comes straight from the player's own game client. questcheck = their real progress on the quest they asked
  about (done count, next step, what's still missing); questlog = quests in their log right now; facts = ForeverAi's own
  verified offline answer. These beat web results and general knowledge: build the answer on them, tell them exactly
  which step they're on and what's left for THEIR character, and never tell them to do a step questcheck says is done.
- Give concrete specifics: NPC names, zones, coordinates, item names, numbers, step-by-step when useful.
- If something isn't known for Forever yet, say so in one short line instead of guessing.
- When LIVE WEB RESULTS are given, use them for current Forever facts and mention the source site briefly (e.g. 'per Wowhead').
- Plain text only: no markdown, no asterisks, no headers, no tables. Short lines. Numbered steps are fine.
- Your answer is shown in an in-game panel: aim for 400-900 characters (up to ~1200 for a step-by-step guide).
- Earlier turns are only context for follow-ups ("what about X", "where is that"). If the new question is about something
  else, answer it on its own and don't drag earlier topics in."""

_model_cache = {"name": None}
_busy = {}  # model -> time until which we skip it (overloaded / timing out)
_search_models = []  # models where this key can use Google Search grounding (filled at startup)
try:
    _model_cache["name"] = json.load(open(os.path.join(APP_DIR, "state.json"))).get("last_model")
except Exception:
    pass
_search_ok = {"until": 0}


def gemini_post(key, model, body, timeout=12):
    req = urllib.request.Request(f"{API}/models/{model}:generateContent", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "x-goog-api-key": key})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def list_models(key):
    """Every stable Gemini Flash / Flash-Lite model this key can use, best first."""
    if _model_cache.get("list"):
        return _model_cache["list"]
    found = []
    try:
        req = urllib.request.Request(f"{API}/models?pageSize=300", headers={"x-goog-api-key": key})
        with urllib.request.urlopen(req, timeout=20) as r:
            for m in json.loads(r.read().decode()).get("models", []):
                name = m.get("name", "").split("/")[-1]
                if "generateContent" not in m.get("supportedGenerationMethods", []):
                    continue
                mm = re.fullmatch(r"gemini-(\d+)(?:\.(\d+))?-flash(-lite)?", name)
                if mm:
                    found.append(((int(mm.group(1)), int(mm.group(2) or 0)), 0 if not mm.group(3) else 1, name))
    except Exception as e:
        log(f"model list failed: {e}")
    # newest Flash first, then newest Flash-Lite, then older ones
    found.sort(key=lambda t: (t[1], tuple(-x for x in t[0])))
    names = [n for _, _, n in found] or ["gemini-3.8-flash", "gemini-3.5-flash-lite"]
    _model_cache["list"] = names
    log("models available: " + ", ".join(names))
    return names


def pick_model(key, preferred=None):
    return preferred or (_model_cache.get("name") or list_models(key)[0])



# --------------------------------------------------------------------------- live web search (free, no key)
import html as _html
import urllib.parse
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36",
      "Accept-Language": "en-US,en;q=0.9"}
GOOD_SITES = ("wowhead.com", "warcraft.wiki.gg", "reddit.com", "icy-veins.com", "method.gg", "warcrafttavern.com",
              "wowpedia", "mobalytics.gg", "kami-labs.fr", "wow-professions.com", "blizzard.com", "conquestcapped.com")


def _get(url, data=None, timeout=5):
    req = urllib.request.Request(url, data=data, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(600000).decode("utf-8", "ignore")


def web_search(query, n=6):
    """Top result URLs + snippets: DuckDuckGo's HTML page, then Bing as backup."""
    results = []
    try:
        page = _get("https://html.duckduckgo.com/html/", data=urllib.parse.urlencode({"q": query}).encode())
        for m in re.finditer(r'class="result__a" href="([^"]+)"[^>]*>(.*?)</a>.*?class="result__snippet"[^>]*>(.*?)</a>', page, re.S):
            url = m.group(1)
            if "uddg=" in url:
                url = urllib.parse.unquote(url.split("uddg=")[1].split("&")[0])
            results.append((url, _strip(m.group(2)), _strip(m.group(3))))
    except Exception as e:
        log(f"ddg search failed: {e}")
    if not results:
        try:
            page = _get("https://www.bing.com/search?q=" + urllib.parse.quote(query) + "&setlang=en")
            for m in re.finditer(r'<li class="b_algo".*?<h2[^>]*><a[^>]+href="([^"]+)"[^>]*>(.*?)</a>.*?(?:<p[^>]*>(.*?)</p>|</li>)', page, re.S):
                url = _html.unescape(m.group(1))
                if "bing.com/ck/a" in url and "u=a1" in url:  # Bing tracking link: real URL is base64 in u=a1...
                    import base64
                    enc = url.split("u=a1", 1)[1].split("&", 1)[0]
                    try:
                        url = base64.urlsafe_b64decode(enc + "=" * (-len(enc) % 4)).decode("utf-8", "ignore")
                    except Exception:
                        pass
                results.append((url, _strip(m.group(2)), _strip(m.group(3) or "")))
        except Exception as e:
            log(f"bing search failed: {e}")
    return results[:n]


def _strip(h):
    h = re.sub(r"(?is)<(script|style|noscript|svg|nav|footer|header)[^>]*>.*?</\1>", " ", h)
    h = re.sub(r"(?s)<[^>]+>", " ", h)
    return re.sub(r"\s+", " ", _html.unescape(h)).strip()


def page_extract(url, qtoks, limit=2200):
    """Readable text from a page, keeping the sentences that mention the question's words."""
    try:
        text = _strip(_get(url))
    except Exception:
        return ""
    sents = re.split(r"(?<=[.!?])\s+", text)
    scored = []
    for i, snt in enumerate(sents):
        if 25 < len(snt) < 600:
            low = snt.lower()
            sc = sum(1 for t in qtoks if t in low)
            if sc:
                scored.append((sc, i, snt))
    keep = sorted(sorted(scored, reverse=True)[:18], key=lambda x: x[1])
    out = " ".join(snt for _, _, snt in keep)
    return out[:limit]


def web_context(question):
    t0 = time.time()
    results = web_search(question + " wow forever")
    if not results:
        return ""
    qtoks = [t for t in toks(question) if len(t) > 2]
    ranked = sorted(results, key=lambda r: 0 if any(sdom in r[0] for sdom in GOOD_SITES) else 1)
    picks = ranked[:3]
    texts = [""] * len(picks)

    def fetch(i, url):
        texts[i] = page_extract(url, qtoks)
    th = [threading.Thread(target=fetch, args=(i, r[0]), daemon=True) for i, r in enumerate(picks)]
    for t in th: t.start()
    deadline = time.time() + 4.5
    for t in th: t.join(max(0.1, deadline - time.time()))
    parts = []
    for (url, title, snip), body in zip(picks, texts):
        parts.append(f"[{title}] ({url})\n{body or snip}")
    for url, title, snip in ranked[3:]:
        parts.append(f"[{title}] ({url}) {snip}")
    log(f"web search: {len(results)} results, {sum(1 for t in texts if t)} pages read in {time.time() - t0:.1f}s")
    return "\n\n".join(parts)[:9000]


def probe_search(key):
    """Find which models let this key use Google Search grounding (free tier varies by model). Cached for a day."""
    st_path = os.path.join(APP_DIR, "state.json")
    try:
        st = json.load(open(st_path))
    except Exception:
        st = {}
    if time.time() - st.get("probe_time", 0) < 86400 and "search_models" in st:
        return st["search_models"]
    ok = []
    for m in list_models(key):
        try:
            gemini_post(key, m, {"contents": [{"role": "user", "parts": [{"text": "Reply with OK."}]}],
                                 "tools": [{"google_search": {}}], "generationConfig": {"maxOutputTokens": 20}}, timeout=10)
            ok.append(m)
        except Exception:
            pass
    st.update({"probe_time": time.time(), "search_models": ok})
    try:
        os.makedirs(APP_DIR, exist_ok=True); json.dump(st, open(st_path, "w"))
    except Exception:
        pass
    log("models with free Google Search: " + (", ".join(ok) or "none - using ForeverAi's own web search"))
    return ok



def gemini_stream(key, model, body, on_text, first_byte_timeout=7):
    """Stream an answer; calls on_text(full_text_so_far) as words arrive. Returns final text."""
    req = urllib.request.Request(f"{API}/models/{model}:streamGenerateContent?alt=sse", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "x-goog-api-key": key})
    text = ""
    with urllib.request.urlopen(req, timeout=first_byte_timeout) as r:
        for raw in r:
            line = raw.decode("utf-8", "ignore").strip()
            if not line.startswith("data:"):
                continue
            try:
                chunk = json.loads(line[5:])
            except Exception:
                continue
            parts = chunk.get("candidates", [{}])[0].get("content", {}).get("parts", [])
            piece = "".join(p.get("text", "") for p in parts if not p.get("thought"))
            if piece:
                text += piece
                on_text(text)
    return text


def race_answer(key, models, body, on_text, n=3):
    """Ask up to n models at once; the first one to start answering wins and streams to on_text."""
    lock, state = threading.Lock(), {"winner": None, "done": threading.Event(), "final": None, "fails": 0}
    picks = models[:n]

    def run(model):
        def cb(t):
            with lock:
                if state["winner"] is None:
                    state["winner"] = model
                if state["winner"] == model:
                    on_text(t)
        try:
            final = gemini_stream(key, model, body, cb)
            with lock:
                if state["winner"] == model and final:
                    state["final"] = final
                    state["done"].set()
                    return
        except urllib.error.HTTPError as e:
            log(f"gemini {model} HTTP {e.code}: {e.read().decode(errors='ignore')[:160]}")
            if e.code in (503, 429):
                _busy[model] = time.time() + 120
        except Exception as e:
            log(f"gemini {model} error: {e}")
            _busy[model] = time.time() + 120
        with lock:
            state["fails"] += 1
            if state["winner"] == model:
                state["winner"] = None  # it died mid-answer: let another model take over
            if state["fails"] >= len(picks):
                state["done"].set()

    for m in picks:
        threading.Thread(target=run, args=(m,), daemon=True).start()
    state["done"].wait(60)
    if state["final"] and state["winner"]:
        if state["winner"] != _model_cache.get("name"):
            _model_cache["name"] = state["winner"]
            try:
                os.makedirs(APP_DIR, exist_ok=True)
                st_path = os.path.join(APP_DIR, "state.json")
                st = json.load(open(st_path)) if os.path.exists(st_path) else {}
                st["last_model"] = state["winner"]; json.dump(st, open(st_path, "w"))
            except Exception:
                pass
        log(f"answered by {state['winner']}")
    return state["final"]


def ask_gemini(cfg, kb, question, ctx, history, on_text=None):
    notes = kb.search(question + " " + " ".join(h["q"] for h in history[-1:]), k=8)
    ref = "\n".join(f"- [{t}] {a}" for t, a, _ in notes)
    player = "; ".join(f"{k}={v}" for k, v in ctx.items() if v)
    contents = []
    for h in history[-6:]:
        contents.append({"role": "user", "parts": [{"text": h["q"]}]})
        contents.append({"role": "model", "parts": [{"text": h["a"]}]})
    search_models = [m for m in _search_models if _busy.get(m, 0) < time.time()]
    web = "" if search_models else web_context(question)
    web_part = f"\n\nLIVE WEB RESULTS (current pages - prefer these for Forever-specific facts):\n{web}" if web else ""
    contents.append({"role": "user", "parts": [{"text": f"PLAYER: {player}\n\nREFERENCE NOTES:\n{ref}{web_part}\n\nQUESTION: {question}"}]})
    body = {"systemInstruction": {"parts": [{"text": SYSTEM}]}, "contents": contents,
            "generationConfig": {"temperature": 0.5, "maxOutputTokens": 3000}}
    key = cfg["gemini_key"]
    models = []
    for m in search_models + [cfg.get("model"), _model_cache.get("name")] + list_models(key):
        if m and m not in models:
            models.append(m)
    now = time.time()
    models = [m for m in models if _busy.get(m, 0) < now] + [m for m in models if _busy.get(m, 0) >= now]
    started = now
    use_search = bool(search_models)
    if on_text and not use_search:
        # fastest path: race the remembered model, the best Flash-Lite and the next Flash; stream the winner
        live = [m for m in models if _busy.get(m, 0) < time.time()]
        lite = [m for m in live if m.endswith("-lite")]
        order = []
        for m in ([_model_cache.get("name")] + lite[:1] + live):
            if m and m not in order:
                order.append(m)
        final = race_answer(key, order, body, on_text)
        if final:
            return final
    last_err = ""
    for model in models:
        if time.time() - started > 50:
            break
        for attempt in range(2):
            b = dict(body)
            if use_search and model in search_models:
                b["tools"] = [{"google_search": {}}]
            try:
                res = gemini_post(key, model, b)
                parts = res.get("candidates", [{}])[0].get("content", {}).get("parts", [])
                text = "".join(p.get("text", "") for p in parts).strip()
                if text:
                    if model != _model_cache.get("name"):
                        _model_cache["name"] = model  # stick with a model that works
                        try:
                            os.makedirs(APP_DIR, exist_ok=True)
                            json.dump({"last_model": model}, open(os.path.join(APP_DIR, "state.json"), "w"))
                        except Exception:
                            pass
                    return text
                last_err = "empty answer"
                break
            except urllib.error.HTTPError as e:
                detail = e.read().decode(errors="ignore")[:300]
                log(f"gemini {model} HTTP {e.code} (search={use_search}): {detail}")
                last_err = f"HTTP {e.code}"
                if use_search and model in search_models:
                    search_models.remove(model)
                    if model in _search_models: _search_models.remove(model)
                    if not search_models:
                        # grounding stopped working: fall back to our own web search for this question
                        web2 = web_context(question)
                        if web2:
                            body["contents"][-1]["parts"][0]["text"] = body["contents"][-1]["parts"][0]["text"].replace(
                                "\n\nQUESTION:", f"\n\nLIVE WEB RESULTS (current pages):\n{web2}\n\nQUESTION:")
                    continue
                if e.code in (401, 403):
                    return "Gemini rejected the API key. Open ForeverAi Companion settings and paste your key again."
                if e.code in (503, 429):
                    _busy[model] = time.time() + 120  # skip this model for 2 minutes
                break  # try the next model
            except Exception as e:
                log(f"gemini {model} error: {e}")
                last_err = str(e)
                _busy[model] = time.time() + 120  # timed out: probably overloaded, skip it for a bit
                break
    if "429" in last_err:
        return "Gemini's free tier is out of requests for now - try again in a minute (or tomorrow if today's free limit is used up)."
    return "Gemini is busy right now (all free models overloaded). Try again in a minute."


def clean_answer(text):
    text = re.sub(r"\*\*|__|`|^#+\s*", "", text, flags=re.M)
    text = re.sub(r"^\s*[\*\-]\s+", "- ", text, flags=re.M)
    text = re.sub(r"\[(\d+)\]", "", text)
    text = text.replace("~", "-").replace("|", "/")
    text = re.sub(r"\n{2,}", "\n", text).strip()
    return text[:2400]


# --------------------------------------------------------------------------- main loop
def parse_question(clip):
    # FAIQ1~<id>~<k=v;k=v>~<question>
    parts = clip.strip()[len(Q_TAG):].split("~", 2)
    parts = ["FAIQ1"] + parts
    if len(parts) != 4 or not re.fullmatch(r"[A-Za-z0-9]{4,12}", parts[1]):
        return None
    ctx = {}
    for kv in parts[2].split(";"):
        if "=" in kv:
            k, v = kv.split("=", 1)
            ctx[k.strip()[:20]] = v.strip()[:120]
    q = parts[3].strip()[:600]
    return (parts[1], ctx, q) if q else None


def load_cfg():
    try:
        cfg = json.load(open(CONFIG, encoding="utf-8"))
    except Exception:
        cfg = {}
    # simplest setup: a text file named gemini_key.txt next to this program, containing just the key
    keyfile = os.path.join(HERE, "gemini_key.txt")
    if os.path.exists(keyfile):
        key = open(keyfile, encoding="utf-8-sig").read().strip()
        if key:
            cfg["gemini_key"] = key
    return cfg


# --------------------------------------------------------------------------- screen bridge: read ForeverAi's cell strip
W_CELLS, CELL = 64, 3
FINDER = re.compile(rb"(?:\xff\x00\xff.){3}(?:\xff\xff\x00.){3}(?:\x00\xff\xff.){3}", re.S)  # magenta, cyan, yellow (BGRA)

if user32:
    gdi32 = ctypes.WinDLL("gdi32", use_last_error=True)
    WNDENUMPROC = ctypes.WINFUNCTYPE(w.BOOL, w.HWND, w.LPARAM)
    user32.EnumWindows.argtypes = [WNDENUMPROC, w.LPARAM]
    user32.GetWindowTextW.argtypes = [w.HWND, w.LPWSTR, ctypes.c_int]
    user32.IsWindowVisible.argtypes = [w.HWND]
    user32.IsIconic.argtypes = [w.HWND]
    user32.GetClientRect.argtypes = [w.HWND, ctypes.POINTER(w.RECT)]
    user32.ClientToScreen.argtypes = [w.HWND, ctypes.POINTER(w.POINT)]
    user32.GetForegroundWindow.restype = w.HWND
    user32.GetDC.argtypes = [w.HWND]; user32.GetDC.restype = w.HDC
    user32.ReleaseDC.argtypes = [w.HWND, w.HDC]
    gdi32.CreateCompatibleDC.argtypes = [w.HDC]; gdi32.CreateCompatibleDC.restype = w.HDC
    gdi32.CreateCompatibleBitmap.argtypes = [w.HDC, ctypes.c_int, ctypes.c_int]; gdi32.CreateCompatibleBitmap.restype = w.HBITMAP
    gdi32.SelectObject.argtypes = [w.HDC, w.HGDIOBJ]; gdi32.SelectObject.restype = w.HGDIOBJ
    gdi32.BitBlt.argtypes = [w.HDC, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, w.HDC, ctypes.c_int, ctypes.c_int, w.DWORD]
    gdi32.GetDIBits.argtypes = [w.HDC, w.HBITMAP, w.UINT, w.UINT, ctypes.c_void_p, ctypes.c_void_p, w.UINT]
    gdi32.DeleteObject.argtypes = [w.HGDIOBJ]
    gdi32.DeleteDC.argtypes = [w.HDC]
    user32.SetWindowPos.argtypes = [w.HWND, w.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, w.UINT]
    user32.ShowWindow.argtypes = [w.HWND, ctypes.c_int]
    user32.GetWindowLongW.argtypes = [w.HWND, ctypes.c_int]
    user32.SetWindowLongW.argtypes = [w.HWND, ctypes.c_int, ctypes.c_long]
    user32.SetLayeredWindowAttributes.argtypes = [w.HWND, w.COLORREF, ctypes.c_byte, w.DWORD]
    user32.GetParent.argtypes = [w.HWND]; user32.GetParent.restype = w.HWND


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [("biSize", w.DWORD), ("biWidth", w.LONG), ("biHeight", w.LONG), ("biPlanes", w.WORD), ("biBitCount", w.WORD),
                ("biCompression", w.DWORD), ("biSizeImage", w.DWORD), ("biXPelsPerMeter", w.LONG), ("biYPelsPerMeter", w.LONG),
                ("biClrUsed", w.DWORD), ("biClrImportant", w.DWORD)]


def find_wow():
    found = []

    def cb(hwnd, _):
        if user32.IsWindowVisible(hwnd):
            buf = ctypes.create_unicode_buffer(256)
            user32.GetWindowTextW(hwnd, buf, 256)
            if buf.value.startswith("World of Warcraft"):
                found.append(hwnd)
        return True
    user32.EnumWindows(WNDENUMPROC(cb), 0)
    return found[0] if found else None


def grab(hwnd):
    """BGRA pixels of the WoW window's client area (works for Windowed / Borderless)."""
    if user32.IsIconic(hwnd):
        return None
    rc = w.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(rc))
    wdt, hgt = rc.right - rc.left, rc.bottom - rc.top
    if wdt < 50 or hgt < 50:
        return None
    pt = w.POINT(0, 0)
    user32.ClientToScreen(hwnd, ctypes.byref(pt))
    sdc = user32.GetDC(None)
    mdc = gdi32.CreateCompatibleDC(sdc)
    bmp = gdi32.CreateCompatibleBitmap(sdc, wdt, hgt)
    old = gdi32.SelectObject(mdc, bmp)
    gdi32.BitBlt(mdc, 0, 0, wdt, hgt, sdc, pt.x, pt.y, 0x00CC0020)  # SRCCOPY
    bi = BITMAPINFOHEADER(ctypes.sizeof(BITMAPINFOHEADER), wdt, -hgt, 1, 32, 0, 0, 0, 0, 0, 0)
    buf = ctypes.create_string_buffer(wdt * hgt * 4)
    gdi32.GetDIBits(mdc, bmp, 0, hgt, buf, ctypes.byref(bi), 0)
    gdi32.SelectObject(mdc, old); gdi32.DeleteObject(bmp); gdi32.DeleteDC(mdc); user32.ReleaseDC(None, sdc)
    return buf.raw, wdt, hgt, pt.x, pt.y


def decode(buf, wdt, hgt):
    """Find and decode ForeverAi's strip. Returns dict or None."""
    for m in FINDER.finditer(buf):
        if m.start() % 4:
            continue
        p = m.start() // 4
        x0, y0 = p % wdt, p // wdt
        if x0 + W_CELLS * CELL > wdt:
            continue

        def cell(i):
            cx, cy = x0 + CELL * (i % W_CELLS) + 1, y0 + CELL * (i // W_CELLS) + 1
            if cy >= hgt:
                return None
            o = (cy * wdt + cx) * 4
            return (4 if buf[o + 2] > 127 else 0) | (2 if buf[o + 1] > 127 else 0) | (1 if buf[o] > 127 else 0)

        def read(nbytes):
            ncells = -(-nbytes * 8 // 3)
            bits = []
            for i in range(3, 3 + ncells):
                v = cell(i)
                if v is None:
                    return None
                bits += [(v >> 2) & 1, (v >> 1) & 1, v & 1]
            out = bytearray()
            for b in range(nbytes):
                byte = 0
                for k in range(8):
                    byte = byte * 2 + bits[b * 8 + k]
                out.append(byte)
            return bytes(out)

        head = read(20)
        if not head or head[0] != 1:
            continue
        n = head[18] * 256 + head[19]
        full = read(20 + n + 2)
        if not full:
            continue
        if sum(full[:-2]) % 65536 != full[-2] * 256 + full[-1]:
            return None  # mid-redraw: try again next frame
        u16 = lambda i: full[i] * 256 + full[i + 1]
        return {"state": full[1] & 1, "scroll": full[1] >> 1, "dx": u16(2) - 32768, "dy": u16(4) - 32768, "w": u16(6), "h": u16(8),
                "id": full[10:18].rstrip(b"\0").decode("ascii", "ignore"),
                "payload": full[20:20 + n].decode("utf-8", "ignore"), "x0": x0, "y0": y0}
    return None


# --------------------------------------------------------------------------- overlay: draws the answer over ForeverAi's panel
PANEL_BG = "#0a0a0d"


class Overlay:
    def __init__(self):
        import tkinter as tk
        self.tk = tk
        self.root = tk.Tk()
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.configure(bg=PANEL_BG)
        self.text = tk.Text(self.root, bg=PANEL_BG, fg="#f2f2f2", bd=0, highlightthickness=0, wrap="word",
                            padx=8, pady=8, font=("Arial", -14), cursor="arrow")
        self.text.pack(fill="both", expand=True)
        self.text.tag_config("q", foreground="#7fb8ff")
        self.text.tag_config("h", foreground="#ffd100")
        self.text.tag_config("dim", foreground="#9a9a9a")
        self.more = tk.Label(self.root, text="scroll for more \u25bc", bg=PANEL_BG, fg="#ffd100", font=("Arial", -12))
        self.scroll = 0
        self.root.update_idletasks()
        self.hwnd = user32.GetParent(self.root.winfo_id()) or self.root.winfo_id()
        GWL_EXSTYLE = -20
        ex = user32.GetWindowLongW(self.hwnd, GWL_EXSTYLE)
        # layered + transparent = mouse clicks pass through to WoW; toolwindow/noactivate = never steals focus or shows in taskbar
        user32.SetWindowLongW(self.hwnd, GWL_EXSTYLE, ex | 0x80000 | 0x20 | 0x80 | 0x08000000)
        user32.SetLayeredWindowAttributes(self.hwnd, 0, 255, 0x2)
        self.shown, self.content = False, None
        self.hide()

    def hide(self):
        if self.shown or self.content is None:
            user32.ShowWindow(self.hwnd, 0)
            self.shown = False

    def show(self, x, y, wdt, hgt, question, answer, scroll=0):
        content = (question, answer, wdt, hgt)
        changed = content != self.content
        if changed:
            self.content = content
            self.text.configure(state="normal", font=("Arial", -13))
            self.text.delete("1.0", "end")
            self.text.insert("end", "> " + question + "\n\n", "q")
            if answer is None:
                self.text.insert("end", "ForeverAi is thinking...", "dim")
            else:
                self.text.insert("end", "ForeverAi:\n", "h")
                self.text.insert("end", answer)
            self.text.configure(state="disabled")
        if changed or scroll != self.scroll:
            self.scroll = scroll
            self.text.yview_moveto(0)
            if scroll:
                self.text.yview_scroll(scroll * 3, "units")   # 3 lines per wheel notch
            self.root.update_idletasks()
            if self.text.yview()[1] < 0.999:
                self.more.place(relx=1.0, rely=1.0, x=-6, y=-4, anchor="se")
            else:
                self.more.place_forget()
        user32.SetWindowPos(self.hwnd, w.HWND(-1), x, y, wdt, hgt, 0x0010 | 0x0040)  # TOPMOST, NOACTIVATE | SHOWWINDOW
        self.shown = True


# --------------------------------------------------------------------------- main
def run():
    if os.name != "nt":
        print("ForeverAi Companion runs on Windows."); return
    if not kernel32.CreateMutexW(None, False, "Local\\ForeverAiCompanion") or ctypes.get_last_error() == 183:
        return  # already running
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)   # work in real screen pixels
    except Exception:
        try:
            user32.SetProcessDPIAware()
        except Exception:
            pass
    cfg = load_cfg()
    if not cfg.get("gemini_key"):
        log("no Gemini key - run ForeverAiCompanion.exe --settings"); return
    if os.path.exists(STOP_FLAG):
        os.remove(STOP_FLAG)
    kb = Knowledge()
    def _probe():
        _search_models[:] = probe_search(cfg["gemini_key"])
    threading.Thread(target=_probe, daemon=True).start()
    lock = threading.Lock()
    shared = {"beacon": None, "wow": None}
    answers, history, chats = {}, [], {}  # chats: conversation id from ForeverAi -> recent Q/A (cleared by "New chat")
    last_turn = [0.0]

    def answer_thread(qid, payload):
        ctx_s, _, q = payload.partition("~")
        ctx = {}
        for kv in ctx_s.split(";"):
            if "=" in kv:
                k, v = kv.split("=", 1)
                k = k.strip()[:20]
                ctx[k] = v.strip()[:700 if k in ("facts", "questlog", "questcheck") else 120]
        q = q.strip()[:600]
        with lock:
            answers[qid] = {"q": q, "a": None}
        if time.time() - last_turn[0] > 1800:
            history.clear()
        def partial(t):
            with lock:
                answers[qid]["a"] = clean_answer(t)
        chat = ctx.pop("chat", "")
        hist = chats.setdefault(chat, []) if chat else []
        a = clean_answer(ask_gemini(cfg, kb, q, ctx, hist[-4:], on_text=partial))
        if chat:
            hist.append({"q": q, "a": a}); del hist[:-8]
        history.append({"q": q, "a": a}); del history[:-8]
        last_turn[0] = time.time()
        with lock:
            answers[qid]["a"] = a
        log(f"answered {qid} ({len(a)} chars)")
        # keep every live Q&A (with what the game told us) so answers can be reviewed and turned into offline knowledge
        try:
            with open(os.path.join(APP_DIR, "chats.jsonl"), "a", encoding="utf-8") as f:
                f.write(json.dumps({"t": time.strftime("%Y-%m-%d %H:%M:%S"), "chat": chat, "q": q, "a": a, "ctx": ctx}) + "\n")
        except Exception as e:
            log(f"chat save failed: {e}")

    def capture_loop():
        miss = 0
        while not os.path.exists(STOP_FLAG):
            time.sleep(0.2)
            try:
                hwnd = find_wow()
                g = grab(hwnd) if hwnd else None
                b = decode(g[0], g[1], g[2]) if g else None
                if b:
                    miss = 0
                    b["ox"], b["oy"] = g[3], g[4]
                    with lock:
                        shared["beacon"], shared["wow"] = b, hwnd
                        new = b["state"] == 1 and b["id"] and b["payload"] and b["id"] not in answers
                        if new:
                            answers[b["id"]] = {"q": b["payload"].partition("~")[2], "a": None}
                    if new:
                        threading.Thread(target=answer_thread, args=(b["id"], b["payload"]), daemon=True).start()
                else:
                    miss += 1
                    if miss >= 8:  # gone for ~1.6s: window closed, UI hidden, or WoW minimized
                        with lock:
                            shared["beacon"] = None
            except Exception as e:
                log(f"capture error: {e}")
                time.sleep(1)

    threading.Thread(target=capture_loop, daemon=True).start()
    ov = Overlay()
    log("companion running (screen bridge)")

    def tick():
        if os.path.exists(STOP_FLAG):
            ov.root.destroy(); return
        with lock:
            b, hwnd = shared["beacon"], shared["wow"]
            ans = answers.get(b["id"]) if b and b["state"] == 1 else None
        fg = user32.GetForegroundWindow()
        if b and ans and hwnd and fg in (hwnd, ov.hwnd):
            x = b["ox"] + b["x0"] + b["dx"]
            y = b["oy"] + b["y0"] + b["dy"]
            ov.show(x, y, b["w"], b["h"], ans["q"], ans["a"], b.get("scroll", 0))
        else:
            ov.hide()
        ov.root.after(100, tick)

    ov.root.after(100, tick)
    ov.root.mainloop()
    log("companion stopped")


def setup():
    print("ForeverAi Companion setup\n")
    print("1) Open https://aistudio.google.com/apikey and sign in with Google.")
    print("2) Click 'Create API key' and copy it (free, no card).\n")
    key = input("Paste your Gemini API key here and press Enter: ").strip()
    if not key:
        print("No key entered."); return
    print("Testing the key...")
    try:
        model = pick_model(key)
        res = gemini_post(key, model, {"contents": [{"role": "user", "parts": [{"text": "Say 'ForeverAi ready' and nothing else."}]}]})
        text = "".join(p.get("text", "") for p in res["candidates"][0]["content"]["parts"])
        print(f"Gemini ({model}) says: {text.strip()}")
    except Exception as e:
        print(f"That key didn't work: {e}"); return
    os.makedirs(APP_DIR, exist_ok=True)
    cfg = load_cfg(); cfg["gemini_key"] = key
    json.dump(cfg, open(CONFIG, "w", encoding="utf-8"), indent=1)
    print(f"\nSaved. Key stored only on this PC: {CONFIG}")
    ans = input("Start ForeverAi Companion automatically when Windows starts? (y/n): ").strip().lower()
    if ans.startswith("y"):
        startup = os.path.join(os.environ["APPDATA"], r"Microsoft\Windows\Start Menu\Programs\Startup", "ForeverAi Companion.vbs")
        pyw = os.path.join(os.path.dirname(sys.executable), "pythonw.exe")
        with open(startup, "w", encoding="utf-8") as f:
            f.write(f'CreateObject("Wscript.Shell").Run """{pyw}"" ""{os.path.abspath(__file__)}""", 0, False\n')
        print("Added to Windows startup.")
    print("\nDone. Run 'Start ForeverAi Companion.bat' now (or it starts with Windows).")


if __name__ == "__main__":
    if "--setup" in sys.argv:
        setup()
    elif "--test" in sys.argv:  # offline check of knowledge loading + retrieval
        kb = Knowledge()
        for t, a, _ in kb.search(" ".join(a for a in sys.argv[2:] if a != "--test"), 5):
            print("-", t, "|", a[:120])
    else:
        run()
