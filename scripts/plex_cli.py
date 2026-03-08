#!/usr/bin/env python3
"""Plex Media Server CLI helper.

Uses env vars by default:
  PLEX_BASE_URL
  PLEX_TOKEN

Config sources are resolved in this order:
  1. CLI flags (--base-url / --token)
  2. Existing shell env vars
  3. .env in the skill root

Examples:
  ./plex_cli.py ping
  ./plex_cli.py libraries
  ./plex_cli.py search --query "Alien" --limit 20
  ./plex_cli.py recently-added --section-id 2 --limit 10
  ./plex_cli.py sessions
  ./plex_cli.py metadata --rating-key 12345
  ./plex_cli.py refresh-section --section-id 2
  ./plex_cli.py watchlist
  ./plex_cli.py watchlist --filter movie --sort watchlistedAt:desc
"""

from __future__ import annotations

import argparse
import json
import math
import os
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from typing import Any, Dict, List, Optional, Sequence, Tuple


SKILL_ROOT = pathlib.Path(__file__).resolve().parent.parent
DOTENV_PATH = SKILL_ROOT / ".env"
DOTENV_EXAMPLE_PATH = SKILL_ROOT / ".env.example"
EXAMPLE_BASE_URL = "http://YOUR_PLEX_IP:32400"
EXAMPLE_TOKEN = "YOUR_PLEX_TOKEN"


class JsonArgumentParser(argparse.ArgumentParser):
    """ArgumentParser that reports validation errors without printing usage."""

    def error(self, message: str) -> None:
        raise ValueError(message)


def _load_dotenv() -> None:
    """Load .env file from skill root (one level up from scripts/)."""
    if not DOTENV_PATH.is_file():
        return
    with open(DOTENV_PATH, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            key, _, value = line.partition('=')
            key, value = key.strip(), value.strip()
            if value and value[0] in ('"', "'") and value[-1] == value[0]:
                value = value[1:-1]
            os.environ.setdefault(key, value)


_load_dotenv()


def normalize_base_url(base_url: str) -> str:
    value = (base_url or "").strip()
    if not value:
        raise ValueError(
            "PLEX_BASE_URL is required. Create .env from .env.example or pass --base-url."
        )
    if value == EXAMPLE_BASE_URL:
        raise ValueError(
            "PLEX_BASE_URL still uses the placeholder from .env.example. "
            "Replace it with your real Plex server URL."
        )
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise ValueError(
            "PLEX_BASE_URL must be a full URL like http://192.168.107.236:32400"
        )
    return value.rstrip("/")


def normalize_token(token: str) -> str:
    value = (token or "").strip()
    if not value:
        raise ValueError(
            "PLEX_TOKEN is required. Create .env from .env.example or pass --token."
        )
    if value == EXAMPLE_TOKEN:
        raise ValueError(
            "PLEX_TOKEN still uses the placeholder from .env.example. "
            "Replace it with your real Plex token."
        )
    return value


def resolve_config(base_url: Optional[str], token: Optional[str]) -> Tuple[str, str]:
    raw_base_url = (base_url or "").strip()
    raw_token = (token or "").strip()

    missing: List[str] = []
    if not raw_base_url:
        missing.append("PLEX_BASE_URL")
    if not raw_token:
        missing.append("PLEX_TOKEN")

    if missing:
        if DOTENV_PATH.is_file():
            raise ValueError(
                "Missing Plex configuration: "
                f"{', '.join(missing)}. Update {DOTENV_PATH} or pass the matching CLI flag."
            )
        raise ValueError(
            "Missing Plex configuration: "
            f"{', '.join(missing)}. Create {DOTENV_PATH} from {DOTENV_EXAMPLE_PATH}, "
            "export the variables, or pass --base-url/--token."
        )

    return normalize_base_url(raw_base_url), normalize_token(raw_token)


def as_int(value: Optional[str]) -> Optional[int]:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def print_json(data: Dict[str, Any]) -> None:
    json.dump(data, sys.stdout, indent=2, ensure_ascii=False, allow_nan=False)
    sys.stdout.write("\n")


def sanitize_json_value(value: Any) -> Any:
    if isinstance(value, float) and not math.isfinite(value):
        return None
    return value


class PlexClient:
    def __init__(self, base_url: str, token: str, timeout: int = 20) -> None:
        self.base_url = normalize_base_url(base_url)
        self.token = normalize_token(token)
        self.timeout = timeout

    def _headers(self) -> Dict[str, str]:
        return {
            "Accept": "application/xml",
            "X-Plex-Token": self.token,
            "X-Plex-Product": "OpenClaw Plex Skill",
            "X-Plex-Client-Identifier": "openclaw-plex-skill",
            "X-Plex-Platform": "Linux",
        }

    def _request(self, path: str, params: Optional[Dict[str, Any]] = None, method: str = "GET") -> str:
        url = f"{self.base_url}{path}"
        if params:
            encoded = urllib.parse.urlencode(params)
            url = f"{url}?{encoded}"
        req = urllib.request.Request(url=url, headers=self._headers(), method=method)
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                charset = resp.headers.get_content_charset() or "utf-8"
                return resp.read().decode(charset, errors="replace")
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            snippet = body[:300].strip().replace("\n", " ")
            raise RuntimeError(f"Plex API HTTP {exc.code} on {path}: {snippet}") from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"Connection failed for {path}: {exc.reason}") from exc

    def _xml(self, path: str, params: Optional[Dict[str, Any]] = None, method: str = "GET") -> ET.Element:
        text = self._request(path=path, params=params, method=method)
        try:
            return ET.fromstring(text)
        except ET.ParseError as exc:
            raise RuntimeError(f"Invalid XML response for {path}") from exc

    def ping(self) -> Dict[str, Any]:
        root = self._xml("/")
        return {
            "success": True,
            "server": {
                "friendlyName": root.attrib.get("friendlyName"),
                "version": root.attrib.get("version"),
                "machineIdentifier": root.attrib.get("machineIdentifier"),
                "platform": root.attrib.get("platform"),
                "updatedAt": as_int(root.attrib.get("updatedAt")),
            },
        }

    def libraries(self) -> Dict[str, Any]:
        root = self._xml("/library/sections")
        items: List[Dict[str, Any]] = []
        for node in root.findall("./Directory"):
            items.append(
                {
                    "key": as_int(node.attrib.get("key")),
                    "title": node.attrib.get("title"),
                    "type": node.attrib.get("type"),
                    "agent": node.attrib.get("agent"),
                    "scanner": node.attrib.get("scanner"),
                    "language": node.attrib.get("language"),
                    "updatedAt": as_int(node.attrib.get("updatedAt")),
                    "scannedAt": as_int(node.attrib.get("scannedAt")),
                }
            )
        return {"success": True, "count": len(items), "libraries": items}

    def _parse_media_item(self, node: ET.Element) -> Dict[str, Any]:
        return {
            "type": node.attrib.get("type"),
            "ratingKey": as_int(node.attrib.get("ratingKey")),
            "title": node.attrib.get("title"),
            "year": as_int(node.attrib.get("year")),
            "librarySectionID": as_int(node.attrib.get("librarySectionID")),
            "librarySectionTitle": node.attrib.get("librarySectionTitle"),
            "parentTitle": node.attrib.get("parentTitle"),
            "grandparentTitle": node.attrib.get("grandparentTitle"),
            "summary": node.attrib.get("summary"),
            "duration": as_int(node.attrib.get("duration")),
            "viewCount": as_int(node.attrib.get("viewCount")),
            "addedAt": as_int(node.attrib.get("addedAt")),
            "lastViewedAt": as_int(node.attrib.get("lastViewedAt")),
        }

    def _collect_media_nodes(self, root: ET.Element) -> List[Dict[str, Any]]:
        nodes: List[Dict[str, Any]] = []
        for tag in ("Video", "Directory"):
            for node in root.findall(f"./{tag}"):
                parsed = self._parse_media_item(node)
                if parsed["title"] or parsed["ratingKey"]:
                    nodes.append(parsed)
        return nodes

    def search(self, query: str, limit: int) -> Dict[str, Any]:
        root = self._xml("/search", params={"query": query, "X-Plex-Container-Size": limit})
        items = self._collect_media_nodes(root)
        return {"success": True, "query": query, "count": len(items), "items": items[:limit]}

    def recently_added(self, section_id: Optional[int], limit: int) -> Dict[str, Any]:
        path = f"/library/sections/{section_id}/recentlyAdded" if section_id else "/library/recentlyAdded"
        root = self._xml(path, params={"X-Plex-Container-Start": 0, "X-Plex-Container-Size": limit})
        items = self._collect_media_nodes(root)
        return {
            "success": True,
            "sectionId": section_id,
            "count": len(items),
            "items": items[:limit],
        }

    def sessions(self) -> Dict[str, Any]:
        root = self._xml("/status/sessions")
        sessions: List[Dict[str, Any]] = []
        for node in root.findall("./Video"):
            user_node = node.find("./User")
            player_node = node.find("./Player")
            sessions.append(
                {
                    "ratingKey": as_int(node.attrib.get("ratingKey")),
                    "title": node.attrib.get("title"),
                    "type": node.attrib.get("type"),
                    "year": as_int(node.attrib.get("year")),
                    "username": user_node.attrib.get("title") if user_node is not None else None,
                    "player": player_node.attrib.get("product") if player_node is not None else None,
                    "state": player_node.attrib.get("state") if player_node is not None else None,
                }
            )
        return {"success": True, "count": len(sessions), "sessions": sessions}

    def metadata(self, rating_key: int) -> Dict[str, Any]:
        root = self._xml(f"/library/metadata/{rating_key}")
        items = self._collect_media_nodes(root)
        return {
            "success": True,
            "ratingKey": rating_key,
            "found": len(items) > 0,
            "items": items,
        }

    def refresh_section(self, section_id: int) -> Dict[str, Any]:
        self._request(f"/library/sections/{section_id}/refresh", method="GET")
        return {"success": True, "sectionId": section_id, "message": "refresh triggered"}

    def watchlist(self, libtype: Optional[str] = None, sort: Optional[str] = None) -> Dict[str, Any]:
        """Get the user's Plex Watchlist via python-plexapi (plex.tv cloud API).

        The watchlist lives on plex.tv, not on the local server.
        Requires: pip install plexapi
        """
        try:
            from plexapi.myplex import MyPlexAccount
        except ImportError:
            raise RuntimeError(
                "python-plexapi is required for watchlist. Install: pip3 install plexapi"
            )

        account = MyPlexAccount(token=self.token)
        kwargs: Dict[str, Any] = {}
        if libtype:
            kwargs["libtype"] = libtype
        if sort:
            kwargs["sort"] = sort

        items_raw = account.watchlist(**kwargs)
        items: List[Dict[str, Any]] = []
        for item in items_raw:
            items.append({
                "type": sanitize_json_value(getattr(item, "type", None)),
                "title": sanitize_json_value(getattr(item, "title", None)),
                "year": sanitize_json_value(getattr(item, "year", None)),
                "guid": sanitize_json_value(getattr(item, "guid", None)),
                "ratingKey": sanitize_json_value(getattr(item, "ratingKey", None)),
                "summary": sanitize_json_value((getattr(item, "summary", None) or "")[:200] or None),
            })
        return {"success": True, "count": len(items), "items": items}


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = JsonArgumentParser(description="Plex Media Server helper")
    parser.add_argument("--base-url", default=os.environ.get("PLEX_BASE_URL"))
    parser.add_argument("--token", default=os.environ.get("PLEX_TOKEN"))
    parser.add_argument("--timeout", type=int, default=20)

    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("ping", help="Check server availability and auth")
    sub.add_parser("libraries", help="List Plex libraries")

    search_cmd = sub.add_parser("search", help="Search media")
    search_cmd.add_argument("--query", required=True)
    search_cmd.add_argument("--limit", type=int, default=20)

    recent_cmd = sub.add_parser("recently-added", help="List recently added media")
    recent_cmd.add_argument("--section-id", type=int)
    recent_cmd.add_argument("--limit", type=int, default=10)

    sub.add_parser("sessions", help="List active playback sessions")

    metadata_cmd = sub.add_parser("metadata", help="Get metadata by rating key")
    metadata_cmd.add_argument("--rating-key", type=int, required=True)

    refresh_cmd = sub.add_parser("refresh-section", help="Trigger library refresh by section id")
    refresh_cmd.add_argument("--section-id", type=int, required=True)

    watchlist_cmd = sub.add_parser("watchlist", help="Get user's Plex Watchlist (from plex.tv)")
    watchlist_cmd.add_argument("--filter", choices=["movie", "show"], help="Filter by media type")
    watchlist_cmd.add_argument("--sort", help="Sort: watchlistedAt:desc, titleSort:asc, originallyAvailableAt:desc, rating:desc")

    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    try:
        args = parse_args(argv)
        base_url, token = resolve_config(args.base_url, args.token)
        client = PlexClient(base_url=base_url, token=token, timeout=args.timeout)

        if args.command == "ping":
            result = client.ping()
        elif args.command == "libraries":
            result = client.libraries()
        elif args.command == "search":
            result = client.search(query=args.query, limit=args.limit)
        elif args.command == "recently-added":
            result = client.recently_added(section_id=args.section_id, limit=args.limit)
        elif args.command == "sessions":
            result = client.sessions()
        elif args.command == "metadata":
            result = client.metadata(rating_key=args.rating_key)
        elif args.command == "refresh-section":
            result = client.refresh_section(section_id=args.section_id)
        elif args.command == "watchlist":
            result = client.watchlist(libtype=args.filter, sort=args.sort)
        else:
            raise ValueError(f"Unknown command: {args.command}")
        print_json(result)
    except Exception as exc:
        print_json({"success": False, "error": str(exc)})
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
