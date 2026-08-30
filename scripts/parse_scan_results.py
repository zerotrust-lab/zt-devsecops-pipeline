#!/usr/bin/env python3
"""Summarize open GitHub code-scanning alerts and optionally fail on CRITICAL.

Reads alerts from the GitHub REST API, groups them by tool and severity,
writes a Markdown summary to the job step summary, and exits non-zero when a
CRITICAL alert is open. Standard library only -- no third-party dependencies.

Usage:
    GH_TOKEN=$(gh auth token) \
    python scripts/parse_scan_results.py --repo owner/name --fail-on-critical
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from collections import defaultdict

GITHUB_API = "https://api.github.com"


def fetch_alerts(repo: str, token: str) -> list[dict]:
    """Return all open code-scanning alerts for a repo, following pagination."""
    alerts: list[dict] = []
    page = 1
    while True:
        url = (
            f"{GITHUB_API}/repos/{repo}/code-scanning/alerts"
            f"?state=open&per_page=100&page={page}"
        )
        req = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                batch = json.loads(resp.read().decode())
        except urllib.error.HTTPError as exc:
            if exc.code == 404:
                print("Code scanning not enabled or no alerts endpoint; nothing to summarize.")
                return []
            raise
        if not batch:
            break
        alerts.extend(batch)
        page += 1
    return alerts


def summarize(alerts: list[dict]) -> tuple[str, int]:
    """Build a Markdown table; return (markdown, critical_count)."""
    by_tool: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    critical = 0
    for alert in alerts:
        tool = alert.get("tool", {}).get("name", "unknown")
        rule = alert.get("rule", {})
        severity = (
            rule.get("security_severity_level")
            or rule.get("severity")
            or "unknown"
        ).lower()
        by_tool[tool][severity] += 1
        if severity == "critical":
            critical += 1

    lines = [
        "# Security findings summary",
        "",
        f"**Total open alerts:** {len(alerts)}",
        "",
        "| Tool | Critical | High | Medium | Low | Other |",
        "|------|---------|------|--------|-----|-------|",
    ]
    known = {"critical", "high", "medium", "low"}
    for tool, severities in sorted(by_tool.items()):
        other = sum(v for k, v in severities.items() if k not in known)
        lines.append(
            f"| {tool} | {severities.get('critical', 0)} | {severities.get('high', 0)} "
            f"| {severities.get('medium', 0)} | {severities.get('low', 0)} | {other} |"
        )
    return "\n".join(lines), critical


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, help="owner/name")
    parser.add_argument("--fail-on-critical", action="store_true")
    args = parser.parse_args()

    token = os.environ.get("GH_TOKEN")
    if not token:
        print("GH_TOKEN not set", file=sys.stderr)
        return 2

    alerts = fetch_alerts(args.repo, token)
    markdown, critical = summarize(alerts)
    print(markdown)

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as handle:
            handle.write(markdown + "\n")

    if args.fail_on_critical and critical > 0:
        print(f"::error::{critical} open CRITICAL alert(s) -- failing the security budget gate.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
