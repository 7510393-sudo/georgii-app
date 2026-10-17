#!/usr/bin/env python3
"""Надписи приложения: все T("по-русски", "in English") из кода (P369).

    python3 scripts/strings.py keys   — английские ключи в JSON (для перевода)
    python3 scripts/strings.py check  — у каждого языка переведены все ключи

Ключ — английская надпись, где каждая вставка \\(…) заменена на %@.
Переводы лежат в ios/Chronotheca/<язык>.lproj/App.strings.
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "ios", "Chronotheca")
LANGS = ["uk", "de", "fr", "es", "it", "pt", "nl", "ja"]


def literal(s, i):
    """Строка Swift с позиции i (на кавычке). Возвращает (ключ, конец) или None."""
    assert s[i] == '"'
    if s.startswith('"""', i):
        return None
    j = i + 1
    out = []
    while j < len(s):
        c = s[j]
        if c == '"':
            return "".join(out), j + 1
        if c == "\n":
            return None
        if c == "\\":
            n = s[j + 1]
            if n == "(":
                # вставка: до парной скобки, со строками внутри
                depth, k = 1, j + 2
                while k < len(s) and depth:
                    if s[k] == '"':
                        r = literal(s, k)
                        if r is None:
                            return None
                        k = r[1]
                        continue
                    if s[k] == "(":
                        depth += 1
                    elif s[k] == ")":
                        depth -= 1
                    k += 1
                out.append("%@")
                j = k
                continue
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0"}.get(n, n))
            if n == "u":  # \u{…}
                m = re.match(r"\{([0-9a-fA-F]+)\}", s[j + 2:])
                out[-1] = chr(int(m.group(1), 16))
                j += 2 + len(m.group(0))
                continue
            j += 2
            continue
        out.append(c)
        j += 1
    return None


def skip(s, i):
    while i < len(s):
        if s[i].isspace():
            i += 1
        elif s.startswith("//", i):
            i = s.index("\n", i) if "\n" in s[i:] else len(s)
        else:
            break
    return i


def argument(s, i):
    """Аргумент из одних строк, сложенных «+». (текст, конец) или None."""
    parts = []
    while True:
        i = skip(s, i)
        if i >= len(s) or s[i] != '"':
            return None
        r = literal(s, i)
        if r is None:
            return None
        parts.append(r[0])
        i = skip(s, r[1])
        if s[i] == "+":
            i += 1
            continue
        return "".join(parts), i


def calls(text):
    for m in re.finditer(r'(?<![A-Za-z0-9_.])T\(', text):
        i = m.end()
        a = argument(text, i)
        if not a:
            continue
        ru, i = a
        i = skip(text, i)
        if text[i] != ",":
            continue
        b = argument(text, i + 1)
        if not b:
            continue
        en, i = b
        i = skip(text, i)
        if text[i] != ")":
            continue
        yield ru, en


def keys():
    found = {}
    for name in sorted(os.listdir(SRC)):
        if name.endswith(".swift"):
            with open(os.path.join(SRC, name), encoding="utf-8") as f:
                for ru, en in calls(f.read()):
                    found.setdefault(en, ru)
    return found


def read_strings(path):
    out = {}
    with open(path, encoding="utf-8") as f:
        text = f.read()
    for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', text, re.M):
        un = lambda x: re.sub(r'\\(.)', lambda q: {"n": "\n", "t": "\t"}.get(q.group(1), q.group(1)), x)
        out[un(m.group(1))] = un(m.group(2))
    return out


def write_strings(path, table):
    esc = lambda x: x.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("/* Надписи приложения (P369). Ключ — английская надпись; %@ — вставка. */\n\n")
        for k in sorted(table):
            f.write(f'"{esc(k)}" = "{esc(table[k])}";\n')


def check():
    want = keys()
    bad = 0
    for lang in LANGS:
        path = os.path.join(SRC, f"{lang}.lproj", "App.strings")
        if not os.path.exists(path):
            print(f"::error::нет перевода {lang}: {path}")
            bad += 1
            continue
        have = read_strings(path)
        missing = [k for k in want if k not in have]
        for k in missing[:20]:
            print(f"::error::{lang}: нет перевода «{k}»")
        if missing:
            print(f"::error::{lang}: не переведено {len(missing)} из {len(want)}")
            bad += 1
        for k, v in have.items():
            if k in want and k.count("%@") != len(re.findall(r"%(?:\d\$)?@", v)):
                print(f"::error::{lang}: не те вставки в «{k}» → «{v}»")
                bad += 1
    print(f"надписей: {len(want)}, языков: {len(LANGS)}")
    return bad


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    if mode == "keys":
        json.dump(keys(), sys.stdout, ensure_ascii=False, indent=1)
    elif mode == "build":
        # build <lang> <json>: из JSON {ключ: перевод} — в App.strings
        lang, src = sys.argv[2], sys.argv[3]
        with open(src, encoding="utf-8") as f:
            table = json.load(f)
        write_strings(os.path.join(SRC, f"{lang}.lproj", "App.strings"), table)
    else:
        sys.exit(1 if check() else 0)
