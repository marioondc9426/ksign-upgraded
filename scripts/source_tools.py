#!/usr/bin/env python3
"""helpers for the auto-updating source (altstore format)

  stamp <in.ipa> <build> <out.ipa>   bumps CFBundleShortVersionString to <base>.<build>, prints the new version
  build <repo> <site_dir>            writes <site_dir>/source.json from every .ipa in every release
"""
import json, os, plistlib, subprocess, sys, tempfile, zipfile, urllib.request


def _plist_name(z):
    for n in z.namelist():
        parts = n.split("/")
        if len(parts) == 3 and parts[0] == "Payload" and parts[1].endswith(".app") and parts[2] == "Info.plist":
            return n
    raise RuntimeError("no Info.plist in ipa")


def stamp(src, build, dst):
    with zipfile.ZipFile(src) as zin:
        name = _plist_name(zin)
        info = plistlib.loads(zin.read(name))
        base = str(info.get("CFBundleShortVersionString", "1.0")).split("+")[0]
        base = ".".join(base.split(".")[:3])
        version = f"{base}.{build}"
        info["CFBundleShortVersionString"] = version
        with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                data = plistlib.dumps(info, fmt=plistlib.FMT_BINARY) if item.filename == name else zin.read(item.filename)
                zout.writestr(item, data)
    print(version)


def _gh(*args):
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def _read_ipa(url):
    with tempfile.NamedTemporaryFile(suffix=".ipa") as f:
        req = urllib.request.Request(url, headers={"User-Agent": "source-builder"})
        with urllib.request.urlopen(req) as r:
            f.write(r.read())
        f.flush()
        with zipfile.ZipFile(f.name) as z:
            info = plistlib.loads(z.read(_plist_name(z)))
    return {
        "bundleIdentifier": info.get("CFBundleIdentifier"),
        "version": str(info.get("CFBundleShortVersionString", "1.0")),
        "name": info.get("CFBundleDisplayName") or info.get("CFBundleName") or "App",
        "minOS": info.get("MinimumOSVersion"),
    }


def build(repo, site):
    owner, name = repo.split("/")
    out = os.path.join(site, "source.json")

    # versions we already read, keyed by download url (so old ipas are not downloaded again)
    cache = {}
    if os.path.exists(out):
        try:
            with open(out) as f:
                for app in json.load(f)["apps"]:
                    for v in app.get("versions", []):
                        cache[v["downloadURL"]] = {
                            "bundleIdentifier": app["bundleIdentifier"],
                            "name": app["name"],
                            "version": v["version"],
                            "minOS": v.get("minOSVersion"),
                        }
        except Exception:
            pass

    pages = json.loads(_gh("api", "--paginate", "--slurp", f"repos/{repo}/releases?per_page=100"))
    releases = [r for page in pages for r in page]

    apps = {}
    for rel in releases:
        # beta is replaced on every build, the archived build-<sha> copy is used instead
        if rel.get("draft") or rel.get("tag_name") == "beta":
            continue
        for asset in rel.get("assets", []):
            if not asset["name"].lower().endswith(".ipa"):
                continue
            url = asset["browser_download_url"]
            meta = cache.get(url) or _read_ipa(url)
            bid = meta["bundleIdentifier"]
            if not bid:
                continue
            app = apps.setdefault(bid, {
                "name": meta["name"],
                "bundleIdentifier": bid,
                "developerName": owner,
                "subtitle": "all versions",
                "localizedDescription": f"every build published in {repo}",
                "iconURL": f"https://github.com/{owner}.png",
                "tintColor": "3c94fc",
                "versions": [],
            })
            version = {
                "version": meta["version"],
                "date": rel.get("published_at") or asset["updated_at"],
                "size": asset["size"],
                "downloadURL": url,
                "localizedDescription": rel.get("name") or rel.get("tag_name") or "",
            }
            if meta.get("minOS"):
                version["minOSVersion"] = meta["minOS"]
            app["versions"].append(version)

    for app in apps.values():
        # newest first, the app reads the first entry as the current version
        app["versions"].sort(key=lambda v: v["date"], reverse=True)
        top = app["versions"][0]
        app.update(version=top["version"], versionDate=top["date"], downloadURL=top["downloadURL"], size=top["size"])

    source = {
        "name": f"{name} builds",
        "identifier": f"io.github.{owner.lower()}.{name.lower()}.source",
        "subtitle": "every version, added automatically",
        "iconURL": f"https://github.com/{owner}.png",
        "website": f"https://github.com/{repo}",
        "apps": sorted(apps.values(), key=lambda a: a["name"].lower()),
        "news": [],
    }
    os.makedirs(site, exist_ok=True)
    with open(out, "w") as f:
        json.dump(source, f, indent=2)
    print(f"{len(apps)} apps, {sum(len(a['versions']) for a in apps.values())} versions")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "stamp" and len(sys.argv) == 5:
        stamp(sys.argv[2], sys.argv[3], sys.argv[4])
    elif cmd == "build" and len(sys.argv) == 4:
        build(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
