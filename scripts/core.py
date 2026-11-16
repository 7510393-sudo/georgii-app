#!/usr/bin/env python3
"""Нижний слой (ios/Chronotheca/Core) не смотрит на экран (P970).

Core — то, что читает и пишет файлы в папке человека: дни, план, дневник,
вложения, корзина, опись. Его потом заберут на iPad, Mac и Android, и он
должен обходиться без экрана iPhone. Проверка ищет в файлах Core имена,
которые объявлены вне Core (верхнего уровня: типы и функции).

Старые ссылки — долги — перечислены в ios/core-debts.txt строками
«Файл.swift Имя». Новая ссылка, которой нет в списке, — ошибка.
Долг погасили — строку убрать (иначе тоже ошибка: список врёт).

    python3 scripts/core.py check   — проверить (идёт в CI)
    python3 scripts/core.py list    — напечатать нынешние ссылки
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "ios", "Chronotheca")
CORE = os.path.join(APP, "Core")
DEBTS = os.path.join(ROOT, "ios", "core-debts.txt")

DECL = re.compile(r'^(?:(?:public|internal|private|fileprivate|final|@MainActor|@objc)\s+)*'
                  r'(?:struct|class|enum|protocol|actor|typealias|func)\s+(\w+)', re.M)


def clean(text):
    """Без комментариев и строк: имя в них — не ссылка."""
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'"""(?:\\.|[^\\])*?"""', '""', text, flags=re.S)
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)
    return re.sub(r'//[^\n]*', '', text)


def swift(folder):
    for d, _, names in os.walk(folder):
        for n in names:
            if n.endswith(".swift"):
                yield os.path.join(d, n)


def found():
    inside = set(swift(CORE))
    core_names, outside = set(), {}
    for path in swift(APP):
        text = open(path, encoding="utf-8").read()
        for name in DECL.findall(text):
            if path in inside:
                core_names.add(name)
            else:
                outside.setdefault(name, os.path.basename(path))
    for name in core_names:
        outside.pop(name, None)
    refs = set()
    for path in sorted(inside):
        text = clean(open(path, encoding="utf-8").read())
        for name in outside:
            if re.search(r'(?<![\w.])' + re.escape(name) + r'\b', text):
                refs.add((os.path.basename(path), name))
    return refs, outside


def debts():
    if not os.path.exists(DEBTS):
        return set()
    out = set()
    for line in open(DEBTS, encoding="utf-8"):
        line = line.split("#")[0].strip()
        if line:
            f, n = line.split()
            out.add((f, n))
    return out


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    refs, outside = found()
    if cmd == "list":
        for f, n in sorted(refs):
            print(f"{f} {n}    # {outside[n]}")
        return 0
    owed = debts()
    new = sorted(refs - owed)
    paid = sorted(owed - refs)
    for f, n in new:
        print(f"Core/{f} смотрит на {n} (из {outside[n]}): нижнему слою нельзя смотреть на экран (P970)")
    for f, n in paid:
        print(f"долг погашен — убрать из ios/core-debts.txt: {f} {n}")
    print(f"ссылок нижнего слоя наружу: {len(refs)}, из них новых: {len(new)}")
    return 1 if new or paid else 0


if __name__ == "__main__":
    sys.exit(main())
