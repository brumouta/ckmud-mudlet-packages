#!/usr/bin/env python3
"""Build Mudlet packages from packages/<name>/package.json into dist/<name>.mpackage.

Usage:
    python3 tools/build.py            # build every package
    python3 tools/build.py FriezaQuest     # build just one

A .mpackage is a zip holding config.lua (name, version, ...) and <name>.xml
(the triggers, aliases and scripts in Mudlet's export format).
"""
import datetime
import json
import os
import sys
import zipfile
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGES = os.path.join(ROOT, "packages")
DIST = os.path.join(ROOT, "dist")

PATTERN_TYPES = {"substring": 0, "regex": 1, "startOfLine": 2, "exactMatch": 3}
FLAGS = ('isTempTrigger="no" isMultiline="no" isPerlSlashGOption="no" isColorizerTrigger="no" '
         'isFilterTrigger="no" isSoundTrigger="no" isColorTrigger="no" isColorTriggerFg="no" isColorTriggerBg="no"')


def yes_no(value):
    return "yes" if value else "no"


def trigger_body(name, script, indent):
    p = "\t" * indent
    return (f"{p}<name>{escape(name)}</name>\n{p}<script>{escape(script)}</script>\n"
            f"{p}<triggerType>0</triggerType>\n{p}<conditonLineDelta>0</conditonLineDelta>\n"
            f"{p}<mStayOpen>0</mStayOpen>\n{p}<mCommand />\n{p}<packageName />\n"
            f"{p}<mFgColor>#ff0000</mFgColor>\n{p}<mBgColor>#ffff00</mBgColor>\n{p}<mSoundFile />\n"
            f"{p}<colorTriggerFgColor>#000000</colorTriggerFgColor>\n"
            f"{p}<colorTriggerBgColor>#000000</colorTriggerBgColor>\n")


def trigger_xml(t, indent):
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
    return (f'{p}<Trigger isActive="{active}" isFolder="no" {FLAGS}>\n'
            + trigger_body(t["name"], t.get("script", ""), indent + 1)
            + f"{p}\t<regexCodeList>\n{strings}{p}\t</regexCodeList>\n"
            + f"{p}\t<regexCodePropertyList>\n{kinds}{p}\t</regexCodePropertyList>\n"
            + f"{p}</Trigger>\n")


def alias_xml(a):
    return (f'\t\t<Alias isActive="yes" isFolder="no">\n\t\t\t<name>{escape(a["name"])}</name>\n'
            f'\t\t\t<script>{escape(a["script"])}</script>\n\t\t\t<command />\n\t\t\t<packageName />\n'
            f'\t\t\t<regex>{escape(a["regex"])}</regex>\n\t\t</Alias>\n')


def script_xml(pkg_dir, s):
    with open(os.path.join(pkg_dir, s["file"]), encoding="utf-8") as f:
        code = f.read()
    return (f'\t\t<Script isActive="yes" isFolder="no">\n\t\t\t<name>{escape(s["name"])}</name>\n'
            f'\t\t\t<packageName />\n\t\t\t<script>{escape(code)}</script>\n'
            f'\t\t\t<eventHandlerList />\n\t\t</Script>\n')


def build(name):
    pkg_dir = os.path.join(PACKAGES, name)
    with open(os.path.join(pkg_dir, "package.json"), encoding="utf-8") as f:
        m = json.load(f)
    if m["name"] != name:
        raise ValueError(f"packages/{name}/package.json says its name is '{m['name']}'")

    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE MudletPackage>\n<MudletPackage version="1.001">\n'
           "\t<TriggerPackage>\n" + "".join(trigger_xml(t, 2) for t in m["triggers"]) + "\t</TriggerPackage>\n"
           "\t<AliasPackage>\n" + "".join(alias_xml(a) for a in m["aliases"]) + "\t</AliasPackage>\n"
           "\t<ScriptPackage>\n" + "".join(script_xml(pkg_dir, s) for s in m["scripts"]) + "\t</ScriptPackage>\n"
           "</MudletPackage>\n")
    config = (f"mpackage = [[{m['name']}]]\nauthor = [[{m['author']}]]\ntitle = [[{m['title']}]]\n"
              f"description = [[{m['description']}]]\nversion = [[{m['version']}]]\n"
              f'created = "{datetime.date.today().isoformat()}"\n')

    os.makedirs(DIST, exist_ok=True)
    out = os.path.join(DIST, f"{name}.mpackage")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("config.lua", config)
        z.writestr(f"{name}.xml", xml)
    print(f"built {os.path.relpath(out, ROOT)}  ({m['title']} v{m['version']})")
    return out


def main(names):
    if not names:
        names = sorted(d for d in os.listdir(PACKAGES) if os.path.isfile(os.path.join(PACKAGES, d, "package.json")))
    for name in names:
        build(name)


if __name__ == "__main__":
    main(sys.argv[1:])
