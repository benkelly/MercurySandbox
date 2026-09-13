#!/usr/bin/env python3
"""Fail if any internal href in the built site points nowhere.

usage: check-links.py <public-dir> <base-path>
"""
import os
import re
import sys
import urllib.parse

root, base = sys.argv[1], sys.argv[2]
pages = [os.path.join(d, f) for d, _, fs in os.walk(root) for f in fs if f.endswith(".html")]
bad = total = 0
for p in pages:
    html = open(p, encoding="utf-8").read()
    # Hugo's minifier drops attribute quotes, so match both forms.
    for m in re.finditer(r'href=(?:"([^"#?]+)|([^\s>"#?]+))', html):
        u = m.group(1) or m.group(2)
        if u.startswith(("http", "mailto")):
            continue
        total += 1
        if u.startswith(base):
            path = u[len(base):]
        elif u.startswith("/"):
            print(f"ROOT-ABSOLUTE {p}: {u} (breaks under the Pages subpath)")
            bad += 1
            continue
        else:
            path = os.path.normpath(os.path.join(os.path.dirname(p)[len(root) + 1:], u))
        path = urllib.parse.unquote(path.rstrip("/"))
        if not any(os.path.exists(c) for c in (os.path.join(root, path), os.path.join(root, path, "index.html"))):
            print(f"BROKEN {p}: {u}")
            bad += 1
print(f"{len(pages)} pages, {total} internal links, {bad} broken")
sys.exit(1 if bad else 0)
