from __future__ import annotations

import os
import sys
import logging
from typing import Any, Optional

import requests
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings
import os

from mcp.server.transport_security import TransportSecuritySettings
allowed_hosts = os.getenv("MCP_ALLOWED_HOSTS","localhost:*,127.0.0.1:*").split(",")
allowed_origins = os.getenv("MCP_ALLOWED_ORIGINS","http://localhost:*").split(",")

mcp = FastMCP(
  "ttrss",
  json_response=True,
  transport_security=TransportSecuritySettings(
    allowed_hosts=[x.strip() for x in allowed_hosts if x.strip()],
    allowed_origins=[x.strip() for x in allowed_origins if x.strip()],
  ),
)


logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    stream=sys.stderr,
)
log = logging.getLogger("ttrss-mcp")


def _env(name: str, default: str) -> str:
    val = os.getenv(name)
    return val if val else default


def normalize_api_url(url: str) -> str:
    url = url.strip()
    if not url.endswith("/"):
        url += "/"
    if not url.endswith("api/"):
        url = url.rstrip("/") + "/api/"
    return url




def _post(api_url: str, payload: dict[str, Any], timeout_s: int = 15) -> dict[str, Any]:
    r = requests.post(api_url, json=payload, timeout=timeout_s)
    r.raise_for_status()
    data = r.json()
    if isinstance(data, dict) and data.get("status") == 1:
        raise RuntimeError(f"TT-RSS API error: {data.get('content')}")
    return data


def _login(api_url: str, user: str, password: str) -> dict[str, Any]:
    return _post(api_url, {"op": "login", "user": user, "password": password})


@mcp.tool()
def get_active_functions() -> dict[str, Any]:
    return {
        "tools": [
            {"name": "get_active_functions", "purpose": "List tools exposed by this MCP server."},
            {"name": "get_login", "purpose": "Login into TT-RSS JSON API and return session_id (sid)."},
            {"name": "search", "purpose": "Search headlines via TT-RSS getHeadlines(search=...)."},
        ],
        "defaults": {
            "TTRSS_API_URL": _env("TTRSS_API_URL", "http://localhost:8280/api/"),
            "TTRSS_USER": _env("TTRSS_USER", "admin"),
            "TTRSS_PASSWORD": "***" if os.getenv("TTRSS_PASSWORD") else "(not set)",
        },
    }


@mcp.tool()
def get_login(api_url: Optional[str] = None, user: Optional[str] = None, password: Optional[str] = None) -> dict[str, Any]:
    api_url = normalize_api_url(api_url or _env("TTRSS_API_URL", "http://localhost:8280/api/"))
    user = user or _env("TTRSS_USER", "admin")
    password = password or _env("TTRSS_PASSWORD", "password")
    try:
        return _login(api_url, user, password)
    except Exception as e:
        log.exception("Login failed")
        return {"status": "error", "error": str(e), "api_url": api_url, "user": user}


@mcp.tool()
def search(
    query: str,
    limit: int = 20,
    api_url: Optional[str] = None,
    user: Optional[str] = None,
    password: Optional[str] = None,
    feed_id: int = -4,
    search_mode: str = "all_feeds",
    show_excerpt: bool = True,
    show_content: bool = False,
) -> dict[str, Any]:
    if not query or not query.strip():
        return {"status": "error", "error": "query is empty"}
    if limit < 1:
        return {"status": "error", "error": "limit must be >= 1"}
    if limit > 200:
        limit = 200

    api_url = normalize_api_url(api_url or _env("TTRSS_API_URL", "http://localhost:8280/api/"))
    user = user or _env("TTRSS_USER", "admin")
    password = password or _env("TTRSS_PASSWORD", "password")

    try:
        login_resp = _login(api_url, user, password)
        content = login_resp.get("content") or {}
        sid = content.get("session_id") or content.get("session") or login_resp.get("session_id")
        if not sid:
            return {"status": "error", "error": "No session_id in login response", "login_response": login_resp}

        payload = {
            "op": "getHeadlines",
            "sid": sid,
            "feed_id": feed_id,
            "limit": limit,
            "show_excerpt": show_excerpt,
            "show_content": show_content,
            "sanitize": True,
            "search": query,
            "search_mode": search_mode,
        }
        headlines = _post(api_url, payload)
        return {"status": "ok", "query": query, "limit": limit, "raw": headlines}
    except Exception as e:
        log.exception("Search failed")
        return {"status": "error", "error": str(e), "api_url": api_url, "query": query}
