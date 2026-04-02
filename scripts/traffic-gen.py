#!/usr/bin/env python3
"""
Traffic generator for the memory pressure lab.

Calls /health and /ping on each app at a configurable interval.
Logs response times and HTTP status codes to stdout and to a CSV file.

Usage:
    python3 traffic-gen.py --rg rg-memory-pressure-lab --prefix memlabapp --count 4
    python3 traffic-gen.py --urls https://app1.azurewebsites.net https://app2.azurewebsites.net
"""

import argparse
import csv
import datetime
import itertools
import os
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

DEFAULT_INTERVAL = 15
DEFAULT_OUTPUT = "traffic-results.csv"

ENDPOINTS = ["/health", "/ping"]


def build_urls_from_azure(resource_group: str, prefix: str, count: int) -> list[str]:
    import subprocess
    import json

    result = subprocess.run(
        [
            "az",
            "webapp",
            "list",
            "--resource-group",
            resource_group,
            "--query",
            "[?starts_with(name, '{}')].defaultHostName".format(prefix),
            "--output",
            "json",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    hostnames = json.loads(result.stdout)
    return [f"https://{h}" for h in hostnames[:count]]


def probe(base_url: str, path: str) -> dict:
    url = base_url.rstrip("/") + path
    start = time.monotonic()
    status = 0
    error = ""
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            status = resp.status
            resp.read()
    except urllib.error.HTTPError as e:
        status = e.code
    except Exception as e:
        status = 0
        error = str(e)
    elapsed_ms = round((time.monotonic() - start) * 1000, 1)
    return {
        "ts": datetime.datetime.utcnow().isoformat() + "Z",
        "url": url,
        "status": status,
        "elapsed_ms": elapsed_ms,
        "error": error,
    }


def run(base_urls: list[str], interval: float, output_path: str):
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)

    url_cycle = list(itertools.product(base_urls, ENDPOINTS))
    fieldnames = ["ts", "url", "status", "elapsed_ms", "error"]

    write_header = not Path(output_path).exists()
    with open(output_path, "a", newline="") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        if write_header:
            writer.writeheader()

        print(
            f"Probing {len(base_urls)} apps every {interval}s. Writing to {output_path}"
        )
        print(f"Apps: {base_urls}")
        print("Ctrl+C to stop.\n")

        while True:
            for base_url, path in url_cycle:
                row = probe(base_url, path)
                writer.writerow(row)
                csvfile.flush()

                status_label = str(row["status"])
                flag = "  " if row["status"] == 200 else "!!"
                print(
                    f"{flag} [{row['ts']}] {row['url']:60s}  "
                    f"HTTP {status_label:3s}  {row['elapsed_ms']:7.1f} ms"
                    + (f"  ERR={row['error']}" if row["error"] else "")
                )

            time.sleep(interval)


def main():
    parser = argparse.ArgumentParser(
        description="Memory pressure lab - traffic generator"
    )
    parser.add_argument("--rg", help="Azure resource group name")
    parser.add_argument("--prefix", default="memlabapp", help="App name prefix")
    parser.add_argument(
        "--count", type=int, default=10, help="Max number of apps to probe"
    )
    parser.add_argument("--urls", nargs="+", help="Explicit base URLs (overrides --rg)")
    parser.add_argument(
        "--interval",
        type=float,
        default=DEFAULT_INTERVAL,
        help="Seconds between probe rounds",
    )
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="CSV output file path")
    args = parser.parse_args()

    if args.urls:
        base_urls = args.urls
    elif args.rg:
        print(f"Fetching app hostnames from resource group '{args.rg}'...")
        base_urls = build_urls_from_azure(args.rg, args.prefix, args.count)
        if not base_urls:
            print("No apps found. Check --rg and --prefix.", file=sys.stderr)
            sys.exit(1)
    else:
        parser.error("Provide either --urls or --rg")

    try:
        run(base_urls, args.interval, args.output)
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
