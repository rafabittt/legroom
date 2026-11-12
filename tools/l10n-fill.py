#!/usr/bin/env python3
"""Fill the pt-BR column of a String Catalog from a translation mapping.

Usage:
    tools/l10n-fill.py <catalog.xcstrings> <mapping.json> [<mapping.json> ...]

A mapping is a JSON array of {"en": ..., "pt": ...} where "en" is the English
literal exactly as written in Swift (with \\(expr) interpolations) and "pt" is
the Portuguese with the same \\(expr) expressions, in any order.

The catalog keys come from Xcode (`xcstringstool sync`), where interpolations
are format specifiers (%@, %lld, %lf, ...). This script matches each key to a
mapping entry by its text with the placeholders blanked out, then writes the
Portuguese with the key's own specifiers (positional, %1$@, when Portuguese
reorders them). Keys with no Swift interpolation (e.g. strings looked up at
runtime from JSON) are added if missing.

Reports keys left without a translation.
"""
import json
import re
import sys

SPEC = re.compile(r"%(?:(\d+)\$)?(?:lld|ld|llu|lu|lf|d|i|u|f|@|%)")


def interpolations(s):
    """Split a Swift literal into text parts and \\(expr) expressions."""
    parts, exprs, buf, i = [], [], "", 0
    while i < len(s):
        if s.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < len(s) and depth:
                if s[j] == "(":
                    depth += 1
                elif s[j] == ")":
                    depth -= 1
                j += 1
            parts.append(buf)
            exprs.append(s[i + 2:j - 1])
            buf, i = "", j
        else:
            buf += s[i]
            i += 1
    parts.append(buf)
    return parts, exprs


def unescape(s):
    # Swift escapes in the literal → the characters Xcode stores in the key
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")


def norm_mapping(en):
    parts, exprs = interpolations(en)
    return "\x00".join(unescape(p) for p in parts), exprs


def norm_key(key):
    specs, out, last = [], [], 0
    for m in SPEC.finditer(key):
        if m.group(0) == "%%":
            continue
        out.append(key[last:m.start()])
        specs.append(m.group(0))
        last = m.end()
    out.append(key[last:])
    return "\x00".join(p.replace("%%", "%") for p in out), specs


def main():
    catalog_path, mapping_paths = sys.argv[1], sys.argv[2:]
    catalog = json.load(open(catalog_path))
    strings = catalog.setdefault("strings", {})
    by_norm = {}
    plain = {}
    for mp in mapping_paths:
        for e in json.load(open(mp)):
            en, pt = e["en"], e["pt"]
            n, exprs = norm_mapping(en)
            by_norm.setdefault(n, (en, pt, exprs))
            # only strings looked up at runtime from data files get added
            if not exprs and e.get("file", "").endswith(".json"):
                plain[unescape(en)] = unescape(pt)

    filled, missing = 0, []
    for key, entry in strings.items():
        locs = entry.setdefault("localizations", {})
        if "pt-BR" in locs or entry.get("shouldTranslate") is False:
            continue
        n, specs = norm_key(key)
        hit = by_norm.get(n)
        if not hit:
            missing.append(key)
            continue
        en, pt, exprs = hit
        if len(exprs) != len(specs):
            missing.append(key)
            continue
        pparts, pexprs = interpolations(pt)
        order = []
        for x in pexprs:
            if x not in exprs:
                order = None
                break
            order.append(exprs.index(x))
        if order is None or sorted(order) != list(range(len(exprs))):
            missing.append(key)
            continue
        positional = order != list(range(len(exprs)))
        # a literal % is stored as %% when the key is a format string
        lit = (lambda t: unescape(t).replace("%", "%%")) if "%%" in key else unescape
        out = lit(pparts[0])
        for k, idx in enumerate(order):
            spec = specs[idx]
            if positional:
                spec = "%" + str(idx + 1) + "$" + re.sub(r"^%(\d+\$)?", "", spec)
            out += spec + lit(pparts[k + 1])
        locs["pt-BR"] = {"stringUnit": {"state": "translated", "value": out}}
        filled += 1

    # strings looked up at runtime (no Swift literal → not in the synced keys)
    added = 0
    for en, pt in plain.items():
        if en not in strings:
            strings[en] = {"extractionState": "manual",
                           "localizations": {"pt-BR": {"stringUnit": {"state": "translated", "value": pt}}}}
            added += 1

    with open(catalog_path, "w") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"filled {filled}, added {added}, missing {len(missing)}")
    for k in missing:
        print("  MISSING:", json.dumps(k, ensure_ascii=False))


if __name__ == "__main__":
    main()
