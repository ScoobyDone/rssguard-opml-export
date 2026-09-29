#!/usr/bin/env python3
"""Export RSS Guard SQLite subscriptions as OPML; stdout only, errors on stderr.
Usage: python3 rssguard-opml.py /path/database.db [account-id]
Python 3.9+, standard library only. Database is opened read-only.
"""
import argparse
import datetime
import json
from pathlib import Path
import sqlite3
import sys
import xml.etree.ElementTree as ET

NS = "https://github.com/martinrotter/rssguard"
VERSIONS = {0: "RSS", 1: "RSS", 2: "RSS1", 3: "ATOM", 4: "JSON", 5: "Sitemap", 9: "MediaWiki"}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database")
    parser.add_argument("account_id", nargs="?", type=int)
    args = parser.parse_args()
    path = Path(args.database).expanduser().resolve(strict=True)
    if not path.is_file():
        raise ValueError("Database path is not a file")
    db = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=10)
    db.row_factory = sqlite3.Row
    try:
        db.execute("BEGIN")  # One consistent snapshot, including the live WAL.
        accounts = [dict(r) for r in db.execute("SELECT id, ordr, type FROM Accounts")]
        cats = [dict(r) for r in db.execute("SELECT id, ordr, parent_id AS parent, title, description, account_id FROM Categories")]
        feeds = [dict(r) for r in db.execute("SELECT id, ordr, category AS parent, title, description, source, custom_data, account_id FROM Feeds")]
    finally:
        db.close()
    if args.account_id is not None:
        accounts = [a for a in accounts if a['id'] == args.account_id]
        if not accounts:
            raise ValueError("Account ID not found")
        cats = [r for r in cats if r['account_id'] == args.account_id]
        feeds = [r for r in feeds if r['account_id'] == args.account_id]
    root = ET.Element("opml", {"version": "2.0", "xmlns:rssguard": NS})
    head = ET.SubElement(root, "head")
    ET.SubElement(head, "title").text = "RSS Guard"
    from email.utils import format_datetime
    ET.SubElement(head, "dateCreated").text = format_datetime(datetime.datetime.now(datetime.timezone.utc), usegmt=True)
    body = ET.SubElement(root, "body")
    visited = set()
    children = {}
    for kind, rows in (("c", cats), ("f", feeds)):
        for r in rows:
            r['kind'] = kind
            children.setdefault((r['account_id'], r['parent']), []).append(r)
    def s(v):
        value = "" if v is None else str(v)
        if any(not (c in "\t\n\r" or 0x20 <= ord(c) <= 0xD7FF or 0xE000 <= ord(c) <= 0xFFFD or 0x10000 <= ord(c) <= 0x10FFFF) for c in value):
            raise ValueError("Value contains an invalid XML 1.0 character")
        return value
    def emit(account, parent, element, depth):
        if depth > 200:
            raise ValueError("Folder nesting exceeds 200 levels")
        for r in sorted(children.get((account['id'], parent), []), key=lambda r: (r['ordr'], r['kind'], r['id'])):
            key = (r['kind'], r['account_id'], r['id'])
            if key in visited:
                raise ValueError("Duplicate/cyclic folder or feed")
            visited.add(key)
            attrs = {'text': s(r['title']), 'description': s(r['description'])}
            if r['kind'] == 'f':
                attrs.update(type='rss', title=s(r['title']), xmlUrl=s(r['source']))
                if account['type'] == 'std-rss':
                    data = json.loads(r['custom_data'] or '{}')
                    if not isinstance(data, dict):
                        raise ValueError("Feed custom_data must be a JSON object")
                    attrs.update(encoding=s(data.get('encoding')), **{
                        'rssguard:xmlUrlType': str(int(data.get('source_type') or 0)),
                        'rssguard:postProcess': s(data.get('post_process'))})
                    version = VERSIONS.get(int(data.get('type') or 0))
                    if version:
                        attrs['version'] = version
            node = ET.SubElement(element, 'outline', attrs)
            if r['kind'] == 'c':
                emit(account, r['id'], node, depth + 1)
    for account in sorted(accounts, key=lambda a: (a['ordr'], a['id'])):
        emit(account, -1, body, 0)
    if len(visited) != len(cats) + len(feeds):
        raise ValueError("Orphaned rows or cyclic folders: export refused")
    ET.indent(root, space="  ")
    result = b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + ET.tostring(root, encoding='utf-8') + b'\n'
    ET.fromstring(result)  # Verify before sending any output.
    sys.stdout.buffer.write(result)

if __name__ == '__main__':
    try:
        main()
    except (Exception, KeyboardInterrupt) as exc:
        print(f"rssguard-opml: {exc}", file=sys.stderr)
        sys.exit(1)
