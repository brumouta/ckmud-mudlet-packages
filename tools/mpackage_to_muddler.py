#!/usr/bin/env python3
"""Turn a Mudlet .mpackage (exported from Mudlet's editor) into a muddler project.

Usage:
    python3 tools/mpackage_to_muddler.py <file.mpackage> <output-dir>
    python3 tools/muddler_to_package.py <output-dir>/<Package>    # then: a package.json build.py builds

Writes <output-dir>/<Package>/ with:
    mfile                         package, title, version, author, icon, description
    src/scripts|aliases|triggers  <kind>.json listing names/patterns + one .lua file per item
    src/resources/                any other files in the package (libraries, images)

Every item's code goes into its own .lua file (muddler's naming: spaces become
underscores), so it's readable and diffable. Trigger folders are kept as
"isFolder" entries with their children, in their original order.

Supports what Mudlet exports for plain packages: scripts (with event handlers),
aliases and triggers (substring/regex/start-of-line/exact/lua/spacer/prompt
patterns, multi-line with line delta, fire length, filters, folders, disabled
items). Anything else (timers, keys, buttons, colour triggers) makes it stop
with an error rather than silently dropping it.
"""
import json
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

PATTERN_TYPES = {0: "substring", 1: "regex", 2: "startOfLine", 3: "exactMatch",
                 4: "lua", 5: "spacer", 7: "prompt"}
SUPPORTED_PACKAGES = {"TriggerPackage", "AliasPackage", "ScriptPackage",
                      "TimerPackage", "KeyPackage", "ActionPackage", "VariablePackage", "HelpPackage"}


def config_value(cfg, key):
    m = re.search(rf"^{key}\s*=\s*\[\[(.*?)\]\]", cfg, re.S | re.M)
    return m.group(1) if m else None


def lua_file(name):
    return name.replace(" ", "_") + ".lua"


class Writer:
    def __init__(self, src_dir):
        self.src = src_dir

    def code(self, kind, name, script):
        """Write an item's script next to its json; return True if it had code."""
        if not (script or "").strip():
            return False
        path = os.path.join(self.src, kind, lua_file(name))
        if os.path.exists(path):
            raise SystemExit(f"two {kind} share the file name {lua_file(name)} - rename one in Mudlet first")
        with open(path, "w", encoding="utf-8") as f:
            f.write(script if script.endswith("\n") else script + "\n")
        return True


def text(e, tag, default=""):
    c = e.find(tag)
    return c.text if c is not None and c.text is not None else default


def trigger(w, e):
    if e.get("isColorTrigger") == "yes" or e.get("isSoundTrigger") == "yes":
        raise SystemExit(f"trigger '{text(e, 'name')}' uses colour/sound matching, which this tool doesn't convert")
    out = {"name": text(e, "name")}
    if e.get("isActive") != "yes":
        out["isActive"] = "no"
    if e.get("isFolder") == "yes":
        out["isFolder"] = "yes"
    if e.get("isMultiline") == "yes":
        out["multiline"] = "yes"
        out["multilineDelta"] = text(e, "conditonLineDelta", "0")
    if e.get("isFilterTrigger") == "yes":
        out["filter"] = "yes"
    if e.get("isPerlSlashGOption") == "yes":
        out["matchall"] = "yes"
    if text(e, "mStayOpen", "0") != "0":
        out["fireLength"] = text(e, "mStayOpen")
    if text(e, "mCommand"):
        out["command"] = text(e, "mCommand")
    pats = [s.text or "" for s in e.findall("regexCodeList/string")]
    kinds = [int(i.text) for i in e.findall("regexCodePropertyList/integer")]
    if pats:
        out["patterns"] = []
        for p, k in zip(pats, kinds):
            if k not in PATTERN_TYPES:
                raise SystemExit(f"trigger '{out['name']}' has an unsupported pattern type {k}")
            out["patterns"].append({"pattern": p, "type": PATTERN_TYPES[k]})
    w.code("triggers", out["name"], text(e, "script"))
    children = [trigger(w, c) for c in e if c.tag in ("Trigger", "TriggerGroup")]
    if children:
        out["children"] = children
    return out


def convert(mpackage, out_root):
    z = zipfile.ZipFile(mpackage)
    cfg = z.read("config.lua").decode("utf-8")
    name = config_value(cfg, "mpackage")
    root = ET.fromstring(z.read(f"{name}.xml"))
    pkg_dir = os.path.join(out_root, name)
    if os.path.exists(pkg_dir):
        raise SystemExit(f"{pkg_dir} already exists - remove it first")
    src = os.path.join(pkg_dir, "src")
    for kind in ("scripts", "aliases", "triggers", "resources"):
        os.makedirs(os.path.join(src, kind))
    w = Writer(src)

    for section in root:
        if section.tag not in SUPPORTED_PACKAGES:
            raise SystemExit(f"unknown section {section.tag}")
        if section.tag in ("TimerPackage", "KeyPackage", "ActionPackage") and len(section):
            raise SystemExit(f"{section.tag} isn't empty - this tool doesn't convert timers, keys or buttons yet")

    scripts, aliases, triggers = [], [], []
    for e in root.find("ScriptPackage") if root.find("ScriptPackage") is not None else []:
        if e.tag != "Script":
            raise SystemExit("script folders aren't supported")
        item = {"name": text(e, "name")}
        if e.get("isActive") != "yes":
            item["isActive"] = "no"
        handlers = [s.text for s in e.findall("eventHandlerList/string")]
        if handlers:
            item["eventHandlerList"] = handlers
        w.code("scripts", item["name"], text(e, "script"))
        scripts.append(item)
    for e in root.find("AliasPackage") if root.find("AliasPackage") is not None else []:
        if e.tag != "Alias":
            raise SystemExit("alias folders aren't supported")
        item = {"name": text(e, "name"), "regex": text(e, "regex")}
        if e.get("isActive") != "yes":
            item["isActive"] = "no"
        if text(e, "command"):
            item["command"] = text(e, "command")
        w.code("aliases", item["name"], text(e, "script"))
        aliases.append(item)
    for e in root.find("TriggerPackage") if root.find("TriggerPackage") is not None else []:
        triggers.append(trigger(w, e))

    for kind, items in (("scripts", scripts), ("aliases", aliases), ("triggers", triggers)):
        with open(os.path.join(src, kind, f"{kind}.json"), "w", encoding="utf-8") as f:
            f.write(json.dumps(items, indent=4, ensure_ascii=False) + "\n")

    # Everything else in the zip (libraries, images) becomes a resource
    for info in z.infolist():
        n = info.filename
        if info.is_dir() or n in ("config.lua", f"{name}.xml") or n.startswith(".mudlet/"):
            continue
        dest = os.path.join(src, "resources", n)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(z.read(n))

    mfile = {"package": name, "title": config_value(cfg, "title") or name,
             "version": config_value(cfg, "version") or "1.0.0",
             "author": config_value(cfg, "author") or ""}
    if config_value(cfg, "icon"):
        mfile["icon"] = config_value(cfg, "icon")
    if config_value(cfg, "description"):
        mfile["description"] = config_value(cfg, "description")
    mfile["outputFile"] = True
    with open(os.path.join(pkg_dir, "mfile"), "w", encoding="utf-8") as f:
        f.write(json.dumps(mfile, indent=4, ensure_ascii=False) + "\n")

    print(f"{name}: {len(scripts)} scripts, {len(aliases)} aliases, "
          f"{sum(1 for _ in root.iter('Trigger')) + sum(1 for _ in root.iter('TriggerGroup'))} triggers/folders, "
          f"{len(os.listdir(os.path.join(src, 'resources')))} resources -> {pkg_dir}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    convert(sys.argv[1], sys.argv[2])
