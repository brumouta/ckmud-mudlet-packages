#!/usr/bin/env python3
"""Build the muddler-layout packages (packages/<name>/mfile + src/) without muddler or Java.

Usage:
    python3 tools/muddle.py            # every package that has an mfile
    python3 tools/muddle.py Chat       # just one

Writes dist/<name>.mpackage. It covers the part of muddler's format these packages use:
  src/{triggers,aliases,scripts}/**/<kind>.json   a sub-folder becomes a Mudlet folder of that name
  an entry's code                                 its "script", else <name with _ for spaces>.lua beside the json
  triggers: patterns (substring/regex/startOfLine/exactMatch), multiline + multilineDelta,
            fireLength, matchall, isActive, isFolder, children
  scripts: eventHandlerList
  __PKGNAME__ / __VERSION__ substituted in json and .lua under src/ (not in src/resources)
  src/resources/* copied into the package root; the mfile "icon" also into .mudlet/Icon/
  description: the mfile's, else README.md
Anything else in a json (a key muddler supports that nothing here uses yet) stops the build,
so a new feature can't be dropped silently.
"""
import datetime
import json
import xml.etree.ElementTree as ET
import os
import sys
import zipfile
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGES = os.path.join(ROOT, "packages")
DIST = os.path.join(ROOT, "dist")

PATTERN_TYPES = {"substring": 0, "regex": 1, "startOfLine": 2, "exactMatch": 3}
KNOWN = {
    "triggers": {"name", "patterns", "script", "multiline", "multilineDelta", "multielineDelta",
                 "fireLength", "matchall", "isActive", "isFolder", "children"},
    "aliases": {"name", "regex", "script", "isActive", "isFolder", "children"},
    "scripts": {"name", "script", "eventHandlerList", "isActive", "isFolder", "children"},
}
GROUP = {"triggers": "TriggerGroup", "aliases": "AliasGroup", "scripts": "ScriptGroup"}
ITEM = {"triggers": "Trigger", "aliases": "Alias", "scripts": "Script"}


def yes(value, default="no"):
    value = value if value is not None else default
    return "yes" if value in (True, "yes", "true") else "no"


class Package:
    def __init__(self, name):
        self.dir = os.path.join(PACKAGES, name)
        with open(os.path.join(self.dir, "mfile"), encoding="utf-8") as f:
            self.mfile = json.load(f)
        if self.mfile["package"] != name:
            raise ValueError(f"packages/{name}/mfile says its package is '{self.mfile['package']}'")
        self.name, self.version = name, self.mfile["version"]
        self.src = os.path.join(self.dir, "src")

    def sub(self, text):
        return text.replace("__PKGNAME__", self.name).replace("__VERSION__", self.version)

    def read(self, path):
        with open(path, encoding="utf-8") as f:
            return self.sub(f.read())

    def code(self, entry, directory, where):
        if isinstance(entry.get("script"), str):
            return self.sub(entry["script"])
        path = os.path.join(directory, entry["name"].replace(" ", "_") + ".lua")
        if os.path.isfile(path):
            return self.read(path)
        if yes(entry.get("isFolder")) == "yes":
            return ""
        raise ValueError(f"{where}: '{entry['name']}' has no script and no {os.path.basename(path)}")

    # ---- one entry -------------------------------------------------------------------------
    def entry_xml(self, kind, e, directory, where, path, depth):
        unknown = set(e) - KNOWN[kind]
        if unknown:
            raise ValueError(f"{where}: '{e.get('name')}' uses {sorted(unknown)}, which tools/muddle.py doesn't build")
        p = "  " * depth
        name = self.sub(e["name"])
        children = e.get("children") or []
        folder = yes(e.get("isFolder")) == "yes"
        tag = GROUP[kind] if folder else ITEM[kind]   # muddler nests children in a plain <Trigger>, Mudlet reads both
        attrs = f'isActive="{yes(e.get("isActive"), "yes")}" isFolder="{"yes" if folder else "no"}"'
        body = [f"<name>{escape(name)}</name>", f"<script>{escape(self.code(e, directory, where))}</script>"]

        if kind == "triggers":
            attrs += (f' isTempTrigger="no" isMultiline="{yes(e.get("multiline"))}"'
                      f' isPerlSlashGOption="{yes(e.get("matchall"))}" isColorizerTrigger="no"'
                      ' isFilterTrigger="no" isSoundTrigger="no" isColorTrigger="no"'
                      ' isColorTriggerFg="no" isColorTriggerBg="no"')
            patterns = e.get("patterns") or []
            if not patterns and not folder:
                raise ValueError(f"{where}: trigger '{name}' has no patterns")
            for x in patterns:
                if x["type"] not in PATTERN_TYPES:
                    raise ValueError(f"{where}: trigger '{name}' has pattern type '{x['type']}'")
            body += ["<triggerType>0</triggerType>",
                     f"<conditonLineDelta>{int(e.get('multilineDelta') or 0)}</conditonLineDelta>",
                     f"<mStayOpen>{int(e.get('fireLength') or 0)}</mStayOpen>",
                     "<mCommand />", "<packageName />", f"<path>{escape(path)}</path>" if path else "<path />",
                     "<mFgColor>#ff0000</mFgColor>", "<mBgColor>#ffff00</mBgColor>", "<mSoundFile />",
                     "<colorTriggerFgColor>#000000</colorTriggerFgColor>",
                     "<colorTriggerBgColor>#000000</colorTriggerBgColor>",
                     "<regexCodeList>" + "".join(f"<string>{escape(self.sub(x['pattern']))}</string>" for x in patterns) + "</regexCodeList>",
                     "<regexCodePropertyList>" + "".join(f"<integer>{PATTERN_TYPES[x['type']]}</integer>" for x in patterns) + "</regexCodePropertyList>"]
        elif kind == "aliases":
            body += ["<command />", "<packageName />", f"<regex>{escape(self.sub(e.get('regex', '')))}</regex>"]
        else:
            events = "".join(f"<string>{escape(self.sub(x))}</string>" for x in e.get("eventHandlerList") or [])
            body += ["<packageName />", f"<eventHandlerList>{events}</eventHandlerList>"]

        inner = "".join(f"{p}  {b}\n" for b in body)
        inner += "".join(self.entry_xml(kind, c, directory, where, path, depth + 1) for c in children)
        return f"{p}<{tag} {attrs}>\n{inner}{p}</{tag}>\n"

    # ---- a src/<kind> folder: its json, then each sub-folder as a Mudlet folder ---------------
    def folder_xml(self, kind, directory, path, depth):
        out = ""
        manifest = os.path.join(directory, f"{kind}.json")
        if os.path.isfile(manifest):
            with open(manifest, encoding="utf-8") as f:
                entries = json.loads(self.sub(f.read()))
            where = os.path.relpath(manifest, ROOT)
            out += "".join(self.entry_xml(kind, e, directory, where, path, depth) for e in entries)
        for sub in sorted(d for d in os.listdir(directory) if os.path.isdir(os.path.join(directory, d))):
            inner = self.folder_xml(kind, os.path.join(directory, sub), sub, depth + 1)
            p = "  " * depth
            attrs = 'isActive="yes" isFolder="yes"'
            extra = ""
            if kind == "triggers":
                attrs += (' isTempTrigger="no" isMultiline="no" isPerlSlashGOption="no" isColorizerTrigger="no"'
                          ' isFilterTrigger="no" isSoundTrigger="no" isColorTrigger="no"'
                          ' isColorTriggerFg="no" isColorTriggerBg="no"')
                extra = (f"{p}  <triggerType>0</triggerType>\n{p}  <conditonLineDelta>0</conditonLineDelta>\n"
                         f"{p}  <mStayOpen>0</mStayOpen>\n{p}  <mCommand />\n{p}  <path>{escape(sub)}</path>\n"
                         f"{p}  <regexCodeList />\n{p}  <regexCodePropertyList />\n")
            elif kind == "aliases":
                extra = f"{p}  <regex />\n"
            else:
                extra = f"{p}  <eventHandlerList />\n"
            out += (f"{p}<{GROUP[kind]} {attrs}>\n{p}  <name>{escape(sub)}</name>\n{p}  <script />\n"
                    f"{p}  <packageName />\n{extra}{inner}{p}</{GROUP[kind]}>\n")
        return out

    def section(self, kind, tag):
        directory = os.path.join(self.src, kind)
        inner = self.folder_xml(kind, directory, "", 2) if os.path.isdir(directory) else ""
        return f"  <{tag}>\n{inner}  </{tag}>\n" if inner else f"  <{tag} />\n"

    def build(self):
        xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE MudletPackage>\n<MudletPackage version="1.001">\n'
               + self.section("triggers", "TriggerPackage") + self.section("aliases", "AliasPackage")
               + self.section("scripts", "ScriptPackage") + "</MudletPackage>\n")
        ET.fromstring(xml.encode("utf-8"))   # a malformed package fails here, not in Mudlet
        m = self.mfile
        description = m.get("description")
        readme = os.path.join(self.dir, "README.md")
        if not description and os.path.isfile(readme):
            with open(readme, encoding="utf-8") as f:
                description = f.read()
        config = f"mpackage = [[{self.name}]]\nauthor = [[{m.get('author', '')}]]\n"
        if m.get("icon"):
            config += f"icon = [[{m['icon']}]]\n"
        config += (f"title = [[{m.get('title', self.name)}]]\ndescription = [[{description or ''}]]\n"
                   f"version = [[{self.version}]]\ncreated = \"{datetime.date.today().isoformat()}\"\n")

        os.makedirs(DIST, exist_ok=True)
        out = os.path.join(DIST, f"{self.name}.mpackage")
        resources = os.path.join(self.src, "resources")
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("config.lua", config)
            z.writestr(f"{self.name}.xml", xml)
            if os.path.isdir(resources):
                for base, _, files in os.walk(resources):
                    for f in sorted(files):
                        if f == ".DS_Store":
                            continue
                        full = os.path.join(base, f)
                        z.write(full, os.path.relpath(full, resources))
            if m.get("icon"):
                icon = os.path.join(resources, m["icon"])
                if not os.path.isfile(icon):
                    raise ValueError(f"packages/{self.name}/mfile: icon {m['icon']} isn't in src/resources")
                z.writestr(".mudlet/", "")
                z.writestr(".mudlet/Icon/", "")
                z.write(icon, f".mudlet/Icon/{m['icon']}")
        print(f"built {os.path.relpath(out, ROOT)}  ({m.get('title', self.name)} v{self.version})")
        return out


def all_names():
    return sorted(d for d in os.listdir(PACKAGES) if os.path.isfile(os.path.join(PACKAGES, d, "mfile")))


def main(names):
    for name in names or all_names():
        Package(name).build()


if __name__ == "__main__":
    main(sys.argv[1:])
