#!/usr/bin/env python3
"""Upload a scan report to DefectDojo via the reimport-scan API.

Optional: use this when you outgrow the native GitHub Security tab and need
cross-repo aggregation, SLA tracking, and risk-acceptance workflows.

Usage:
    DD_URL=https://defectdojo.example.com DD_API_KEY=xxxx \
    python scripts/upload_defectdojo.py \
        --file trivy.sarif --scan-type "Trivy Scan" --engagement 42

Requires: pip install requests
"""
from __future__ import annotations

import argparse
import os
import sys
from datetime import date

import requests


def upload(dd_url: str, api_key: str, file_path: str, scan_type: str,
           engagement: int) -> dict:
    """POST a scan file to DefectDojo's reimport-scan endpoint."""
    endpoint = f"{dd_url.rstrip('/')}/api/v2/reimport-scan/"
    with open(file_path, "rb") as handle:
        response = requests.post(
            endpoint,
            headers={"Authorization": f"Token {api_key}"},
            data={
                "scan_type": scan_type,
                "engagement": engagement,
                "active": "true",
                "verified": "false",
                "scan_date": date.today().isoformat(),
                "close_old_findings": "true",   # auto-resolve fixed issues
                "minimum_severity": "Low",
            },
            files={"file": handle},
            timeout=60,
        )
    response.raise_for_status()
    return response.json()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", required=True)
    parser.add_argument("--scan-type", required=True,
                        help='e.g. "Trivy Scan", "Semgrep JSON Report"')
    parser.add_argument("--engagement", type=int, required=True)
    args = parser.parse_args()

    dd_url = os.environ.get("DD_URL")
    api_key = os.environ.get("DD_API_KEY")
    if not dd_url or not api_key:
        print("DD_URL and DD_API_KEY must be set", file=sys.stderr)
        return 2

    result = upload(dd_url, api_key, args.file, args.scan_type, args.engagement)
    print(f"Uploaded. Test id: {result.get('test')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
