#!/usr/bin/env python3
"""Tiny adb driver for manual/automated phone testing.
   adb_ui.py texts | tap "Text" [i] | tapexact "Text" [i] | tapxy X Y | type "txt"
   adb_ui.py field "Label" "value" | key KEYCODE | scroll up|down | shot out.png
"""
import re, subprocess, sys, time, xml.etree.ElementTree as ET

def sh(*a):
    return subprocess.run(["adb", *a], capture_output=True, text=True).stdout

def nodes():
    for _ in range(3):
        sh("shell", "uiautomator", "dump", "/sdcard/ui.xml")
        x = sh("exec-out", "cat", "/sdcard/ui.xml")
        if "<hierarchy" in x:
            break
        time.sleep(1)
    out = []
    for n in ET.fromstring(x[x.index("<hierarchy"):]).iter("node"):
        t = n.get("text") or n.get("content-desc") or ""
        b = re.findall(r"\d+", n.get("bounds", ""))
        if b:
            x1, y1, x2, y2 = map(int, b)
            out.append((t, (x1 + x2) // 2, (y1 + y2) // 2, n.get("clickable")))
    return out

def tap(text, idx=0, exact=False):
    m = [n for n in nodes() if (n[0] == text if exact else text.lower() in n[0].lower())]
    if not m:
        print("NOT FOUND:", text); sys.exit(1)
    t, x, y, _ = m[min(idx, len(m) - 1)]
    sh("shell", "input", "tap", str(x), str(y)); print(f"tapped '{t[:60]}' at {x},{y}")

def type_text(s):
    esc = s.replace("\\", "\\\\").replace(" ", "%s")
    for ch in "&|;<>()$`'\"*?!#~":
        esc = esc.replace(ch, "\\" + ch)
    sh("shell", "input", "text", esc)

c, a = sys.argv[1], sys.argv[2:]
if c == "tap": tap(a[0], int(a[1]) if len(a) > 1 else 0)
elif c == "tapexact": tap(a[0], int(a[1]) if len(a) > 1 else 0, exact=True)
elif c == "tapxy": sh("shell", "input", "tap", a[0], a[1])
elif c == "type": type_text(a[0])
elif c == "field": tap(a[0]); time.sleep(0.4); type_text(a[1])
elif c == "key": sh("shell", "input", "keyevent", a[0])
elif c == "scroll":
    y1, y2 = ("1200", "500") if (a[0] if a else "down") == "down" else ("500", "1200")
    sh("shell", "input", "swipe", "360", y1, "360", y2, "300")
elif c == "shot":
    open(a[0], "wb").write(subprocess.run(["adb", "exec-out", "screencap", "-p"], capture_output=True).stdout); print(a[0])
elif c == "texts":
    for t, x, y, cl in nodes():
        if t.strip(): print(f"{'*' if cl == 'true' else ' '} {x:4},{y:4}  {t[:90]!r}")
