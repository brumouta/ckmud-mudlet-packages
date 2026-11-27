#!/usr/bin/env python3
"""Turn a muddler project (mfile + src/{triggers,aliases,scripts}/*.json + .lua files) into a
package.json that tools/build.py builds. The .lua files stay where they are; only the manifest
changes. Use it after tools/mpackage_to_muddler.py to bring in a package exported from Mudlet.

    python3 tools/muddler_to_package.py packages/<Package>

Writes packages/<Package>/package.json, then removes the mfile and the muddler .json manifests
(and the CKMud update script, which build.py adds to every package).
"""
import json
import os
import sys


def yes(v):
    return v in (True, "yes", "true")


def main(pkg_dir):
    with open(os.path.join(pkg_dir, "mfile"), encoding="utf-8") as f:
        mfile = json.load(f)
    name, version = mfile["package"], mfile["version"]
    src = os.path.join(pkg_dir, "src")
    manifests = []

    def sub(text):
        return text.replace("__PKGNAME__", name).replace("__VERSION__", version)

    def lua_file(directory, entry):
        path = os.path.join(directory, entry["name"].replace(" ", "_") + ".lua")
        return path if os.path.isfile(path) else None

    def body(entry, directory, out):
        if isinstance(entry.get("script"), str):
            out["script"] = sub(entry["script"])
        else:
            path = lua_file(directory, entry)
            if path:
                with open(path, encoding="utf-8") as f:
                    text = f.read()
                    if "__PKGNAME__" in text or "__VERSION__" in text:
                        raise ValueError(f"{path} uses __PKGNAME__/__VERSION__: replace it by hand first")
                out["file"] = os.path.relpath(path, pkg_dir)
            elif not yes(entry.get("isFolder")):
                raise ValueError(f"{entry['name']} has no script and no .lua file")
        return out

    def load(kind):
        directory = os.path.join(src, kind)
        manifest = os.path.join(directory, f"{kind}.json")
        for sub_dir in os.listdir(directory) if os.path.isdir(directory) else []:
            if os.path.isdir(os.path.join(directory, sub_dir)):
                raise ValueError(f"{directory}/{sub_dir}: sub-folders aren't converted, flatten them first")
        if not os.path.isfile(manifest):
            return directory, []
        manifests.append(manifest)
        with open(manifest, encoding="utf-8") as f:
            return directory, json.load(f)

    def trigger(t, directory):
        out = {"name": sub(t["name"])}
        if yes(t.get("isFolder")):
            out["folder"] = True
        else:
            out["patterns"] = [{"type": p["type"], "pattern": sub(p["pattern"])} for p in t.get("patterns", [])]
            body(t, directory, out)
            if yes(t.get("multiline")):
                out["multiline"] = True
                if int(t.get("multilineDelta") or 0):
                    out["delta"] = int(t["multilineDelta"])
            if int(t.get("fireLength") or 0):
                out["fireLength"] = int(t["fireLength"])
            if yes(t.get("matchall")):
                out["matchall"] = True
        if t.get("isActive") == "no":
            out["active"] = False
        if t.get("children"):
            out["children"] = [trigger(c, directory) for c in t["children"]]
        return out

    d, entries = load("triggers")
    triggers = [trigger(t, d) for t in entries]
    d, entries = load("aliases")
    aliases = []
    for a in entries:
        out = {"name": sub(a["name"]), "regex": sub(a["regex"])}
        body(a, d, out)
        if a.get("isActive") == "no":
            out["active"] = False
        aliases.append(out)
    d, entries = load("scripts")
    scripts = []
    updates = [os.path.join(d, f) for f in ("CKMudUpdate.lua", "CKMud_update.lua")]
    for s in entries:
        if s["name"] in ("CKMudUpdate", "CKMud update"):   # build.py adds it
            continue
        if s.get("eventHandlerList"):
            raise ValueError(f"script {s['name']} has event handlers: register them in code first")
        path = lua_file(d, s)
        if not path:
            raise ValueError(f"script {s['name']} has no .lua file (inline scripts aren't converted)")
        scripts.append({"name": sub(s["name"]), "file": os.path.relpath(path, pkg_dir)})

    description = mfile.get("description")
    readme = os.path.join(pkg_dir, "README.md")
    if not description and os.path.isfile(readme):
        with open(readme, encoding="utf-8") as f:
            description = f.read()
    pkg = {"name": name, "version": version, "title": mfile.get("title", name),
           "description": description or "", "author": mfile.get("author", "")}
    resources = os.path.join(src, "resources")
    if os.path.isdir(resources) and [f for f in os.listdir(resources) if f != ".DS_Store"]:
        pkg["resources"] = "src/resources"
    if mfile.get("icon"):
        pkg["icon"] = mfile["icon"]
    pkg.update({"scripts": scripts, "aliases": aliases, "triggers": triggers})

    with open(os.path.join(pkg_dir, "package.json"), "w", encoding="utf-8") as f:
        json.dump(pkg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    for path in manifests + [os.path.join(pkg_dir, "mfile")] + [u for u in updates if os.path.isfile(u)]:
        os.remove(path)
    print(f"{pkg_dir}: package.json written ({len(scripts)} scripts, {len(aliases)} aliases, {len(triggers)} triggers)")


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        main(arg.rstrip("/"))
