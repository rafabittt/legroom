#!/usr/bin/env python3
"""Add a release to appcast.xml, the Sparkle update feed at the repo root.

Usage:
    tools/appcast.py <dmg> <version> <build> [--notes <file.html>]

Signs the DMG with Sparkle's `sign_update` (EdDSA key in the login Keychain,
account "legroom") and puts a new <item> at the top of the feed. The download
URL is the DMG attached to the GitHub Release `v<version>`, so publish that
release with the same file before committing the updated appcast.
"""
import glob
import html
import os
import re
import subprocess
import sys
from email.utils import formatdate

REPO = "rafabittt/legroom"
ACCOUNT = "legroom"
MIN_SYSTEM = "14.0"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FEED = os.path.join(ROOT, "appcast.xml")

EMPTY = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Legroom</title>
    <link>https://github.com/{repo}</link>
    <description>Legroom updates</description>
    <language>en</language>
  </channel>
</rss>
"""


def find_sign_update():
    patterns = [
        os.path.join(ROOT, "build.noindex/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"),
        os.path.expanduser("~/Library/Developer/Xcode/DerivedData/Legroom-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"),
    ]
    for p in patterns:
        hits = sorted(glob.glob(p))
        if hits:
            return hits[-1]
    sys.exit("✗ sign_update not found. Build once (tools/build.sh) so Swift Package Manager downloads Sparkle.")


def main():
    args = sys.argv[1:]
    notes = None
    if "--notes" in args:
        i = args.index("--notes")
        notes = open(args[i + 1]).read()
        del args[i:i + 2]
    dmg, version, build = args
    out = subprocess.run([find_sign_update(), "--account", ACCOUNT, dmg],
                         check=True, capture_output=True, text=True).stdout.strip()
    sig = re.search(r'sparkle:edSignature="([^"]+)"', out).group(1)
    length = re.search(r'length="(\d+)"', out).group(1)
    url = f"https://github.com/{REPO}/releases/download/v{version}/{os.path.basename(dmg)}"
    release_page = f"https://github.com/{REPO}/releases/tag/v{version}"
    description = notes if notes else f'<p><a href="{release_page}">What\'s new in Legroom {version}</a></p>'

    item = f"""    <item>
      <title>Legroom {html.escape(version)}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{html.escape(build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MIN_SYSTEM}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{release_page}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[{description}]]></description>
      <enclosure url="{url}" length="{length}" type="application/octet-stream" sparkle:edSignature="{sig}"/>
    </item>
"""
    feed = open(FEED).read() if os.path.exists(FEED) else EMPTY.format(repo=REPO)
    # replace an existing entry for the same build (re-running a release)
    feed = re.sub(r"    <item>\n(?:(?!</item>).)*?<sparkle:version>" + re.escape(build) + r"</sparkle:version>.*?</item>\n",
                  "", feed, flags=re.S)
    feed = feed.replace("  </channel>", item + "  </channel>", 1) if "<item>" not in feed else \
        feed.replace("    <item>", item + "    <item>", 1)
    open(FEED, "w").write(feed)
    print(f"✓ appcast.xml: Legroom {version} ({build}) → {url}")


if __name__ == "__main__":
    main()
