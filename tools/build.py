#!/usr/bin/env python3
"""Build Mudlet packages from packages/<name>/package.json into dist/<name>.mpackage.

Usage:
    python3 tools/build.py            # build every package
    python3 tools/build.py FriezaQuest     # build just one

A .mpackage is a zip holding config.lua (name, version, ...) and <name>.xml
(the triggers, aliases and scripts in Mudlet's export format), plus any bundled files.

package.json:
  name, version, title, description, author
  icon          optional: a file in "resources", shown in Mudlet's package manager
  resources     optional: a folder whose files go into the package as they are (images, Lua
                modules loaded with require("<Package>.<file>"))
  scripts       [{ name, file }]
  aliases       [{ name, regex, script | file, active? }]
  triggers      [{ name, patterns: [{ type, pattern }], script | file, active?,
                   multiline? (all patterns must match), delta? (lines apart, multiline),
                   fireLength? (lines the children stay open), matchall?, children? }]
                or a folder: { name, folder: true, children }
Pattern types: substring, regex, startOfLine, exactMatch. A key build.py doesn't know stops the
build, and so does a "file" that isn't there, so nothing is dropped silently.
"""
import datetime
import json
import os
import sys
import zipfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGES = os.path.join(ROOT, "packages")
DIST = os.path.join(ROOT, "dist")
# Added to every package: CKMudUpdate("<Package>"), behind each package's `<prefix> update`
UPDATE_SCRIPT = {"name": "CKMud update", "file": os.path.join(ROOT, "tools", "shared", "CKMudUpdate.lua")}

PATTERN_TYPES = {"substring": 0, "regex": 1, "startOfLine": 2, "exactMatch": 3}
def yes_no(value):
    return "yes" if value else "no"


TRIGGER_KEYS = {"name", "patterns", "script", "file", "active", "multiline", "delta", "fireLength",
                "matchall", "children", "folder"}
ALIAS_KEYS = {"name", "regex", "script", "file", "active"}
PACKAGE_KEYS = {"name", "version", "title", "description", "author", "icon", "resources",
                "scripts", "aliases", "triggers"}


def flags(multiline=False, matchall=False):
    return (f'isTempTrigger="no" isMultiline="{yes_no(multiline)}" isPerlSlashGOption="{yes_no(matchall)}" '
            'isColorizerTrigger="no" isFilterTrigger="no" isSoundTrigger="no" isColorTrigger="no" '
            'isColorTriggerFg="no" isColorTriggerBg="no"')


FLAGS = flags()
PKG_DIR = None   # the package being built, for "file" entries



def lua_str(text):
    """A Lua long string for text: [[...]], or [=[...]=] and so on when the text has ]] in it."""
    text = str(text)
    eq = ""
    while f"]{eq}]" in text:
        eq += "="
    return f"[{eq}[{text}]{eq}]"



def code(entry, what):
    """An entry's Lua: its "script", or the contents of its "file" (relative to the package)."""
    if "file" in entry:
        path = os.path.join(PKG_DIR, entry["file"])
        if not os.path.isfile(path):
            raise ValueError(f"{what} '{entry['name']}': {entry['file']} isn't there")
        with open(path, encoding="utf-8") as f:
            return f.read()
    return entry.get("script", "")


def check_keys(entry, known, what):
    unknown = set(entry) - known
    if unknown:
        raise ValueError(f"{what} '{entry.get('name')}' uses {sorted(unknown)}, which build.py doesn't know")


def trigger_body(name, script, indent, delta=0, stay=0):
    p = "\t" * indent
    return (f"{p}<name>{escape(name)}</name>\n{p}<script>{escape(script)}</script>\n"
            f"{p}<triggerType>0</triggerType>\n{p}<conditonLineDelta>{int(delta)}</conditonLineDelta>\n"
            f"{p}<mStayOpen>{int(stay)}</mStayOpen>\n{p}<mCommand />\n{p}<packageName />\n"
            f"{p}<mFgColor>#ff0000</mFgColor>\n{p}<mBgColor>#ffff00</mBgColor>\n{p}<mSoundFile />\n"
            f"{p}<colorTriggerFgColor>#000000</colorTriggerFgColor>\n"
            f"{p}<colorTriggerBgColor>#000000</colorTriggerBgColor>\n")


def trigger_xml(t, indent):
    check_keys(t, TRIGGER_KEYS, "trigger")
    p = "\t" * indent
    active = yes_no(t.get("active", True))
    if t.get("folder"):
        children = "".join(trigger_xml(c, indent + 1) for c in t.get("children", []))
        return (f'{p}<TriggerGroup isActive="{active}" isFolder="yes" {FLAGS}>\n'
                + trigger_body(t["name"], "", indent + 1)
                + f"{p}\t<regexCodeList />\n{p}\t<regexCodePropertyList />\n"
                + children + f"{p}</TriggerGroup>\n")
    if not t.get("patterns"):
        raise ValueError(f"trigger '{t['name']}' has no patterns")
    strings = "".join(f"{p}\t\t<string>{escape(x['pattern'])}</string>\n" for x in t["patterns"])
    kinds = "".join(f"{p}\t\t<integer>{PATTERN_TYPES[x['type']]}</integer>\n" for x in t["patterns"])
    # a trigger with children is a chain: they stay open for fireLength lines after it fires
    children = "".join(trigger_xml(c, indent + 1) for c in t.get("children", []))
    return (f'{p}<Trigger isActive="{active}" isFolder="no" {flags(t.get("multiline"), t.get("matchall"))}>\n'
            + trigger_body(t["name"], code(t, "trigger"), indent + 1, t.get("delta", 0), t.get("fireLength", 0))
            + f"{p}\t<regexCodeList>\n{strings}{p}\t</regexCodeList>\n"
            + f"{p}\t<regexCodePropertyList>\n{kinds}{p}\t</regexCodePropertyList>\n"
            + children + f"{p}</Trigger>\n")


def alias_xml(a):
    check_keys(a, ALIAS_KEYS, "alias")
    return (f'\t\t<Alias isActive="{yes_no(a.get("active", True))}" isFolder="no">\n\t\t\t<name>{escape(a["name"])}</name>\n'
            f'\t\t\t<script>{escape(code(a, "alias"))}</script>\n\t\t\t<command />\n\t\t\t<packageName />\n'
            f'\t\t\t<regex>{escape(a["regex"])}</regex>\n\t\t</Alias>\n')


def script_xml(pkg_dir, s):
    with open(os.path.join(pkg_dir, s["file"]), encoding="utf-8") as f:
        code = f.read()
    return (f'\t\t<Script isActive="yes" isFolder="no">\n\t\t\t<name>{escape(s["name"])}</name>\n'
            f'\t\t\t<packageName />\n\t\t\t<script>{escape(code)}</script>\n'
            f'\t\t\t<eventHandlerList />\n\t\t</Script>\n')


def build(name):
    global PKG_DIR
    pkg_dir = os.path.join(PACKAGES, name)
    PKG_DIR = pkg_dir
    with open(os.path.join(pkg_dir, "package.json"), encoding="utf-8") as f:
        m = json.load(f)
    if m["name"] != name:
        raise ValueError(f"packages/{name}/package.json says its name is '{m['name']}'")
    unknown = set(m) - PACKAGE_KEYS
    if unknown:
        raise ValueError(f"packages/{name}/package.json uses {sorted(unknown)}, which build.py doesn't know")

    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE MudletPackage>\n<MudletPackage version="1.001">\n'
           "\t<TriggerPackage>\n" + "".join(trigger_xml(t, 2) for t in m["triggers"]) + "\t</TriggerPackage>\n"
           "\t<AliasPackage>\n" + "".join(alias_xml(a) for a in m["aliases"]) + "\t</AliasPackage>\n"
           "\t<ScriptPackage>\n" + "".join(script_xml(pkg_dir, s) for s in [UPDATE_SCRIPT] + m["scripts"]) + "\t</ScriptPackage>\n"
           "</MudletPackage>\n")
    ET.fromstring(xml.encode("utf-8"))   # a malformed package fails here, not in Mudlet
    config = f"mpackage = {lua_str(m['name'])}\nauthor = {lua_str(m['author'])}\n"
    if m.get("icon"):
        config += f"icon = {lua_str(m['icon'])}\n"
    config += (f"title = {lua_str(m['title'])}\n"
               f"description = {lua_str(m['description'])}\nversion = {lua_str(m['version'])}\n"
               f'created = "{datetime.date.today().isoformat()}"\n')
    resources = os.path.join(pkg_dir, m["resources"]) if m.get("resources") else None
    if resources and not os.path.isdir(resources):
        raise ValueError(f"packages/{name}/package.json: resources folder {m['resources']} isn't there")
    if m.get("icon") and not (resources and os.path.isfile(os.path.join(resources, m["icon"]))):
        raise ValueError(f"packages/{name}/package.json: icon {m['icon']} isn't in the resources folder")

    os.makedirs(DIST, exist_ok=True)
    out = os.path.join(DIST, f"{name}.mpackage")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("config.lua", config)
        z.writestr(f"{name}.xml", xml)
        if resources:
            for base, _, files in sorted(os.walk(resources)):
                for f in sorted(files):
                    if f != ".DS_Store":
                        full = os.path.join(base, f)
                        z.write(full, os.path.relpath(full, resources))
        if m.get("icon"):
            z.writestr(".mudlet/", "")
            z.writestr(".mudlet/Icon/", "")
            z.write(os.path.join(resources, m["icon"]), f".mudlet/Icon/{m['icon']}")
    print(f"built {os.path.relpath(out, ROOT)}  ({m['title']} v{m['version']})")
    return out


def main(names):
    if not names:
        names = sorted(d for d in os.listdir(PACKAGES) if os.path.isfile(os.path.join(PACKAGES, d, "package.json")))
    for name in names:
        build(name)


if __name__ == "__main__":
    main(sys.argv[1:])
