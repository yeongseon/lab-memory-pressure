#!/usr/bin/env python3
"""
Azure metrics collector for the memory pressure lab.

Pulls App Service Plan and per-app metrics from Azure Monitor
and writes them to a CSV file for post-analysis.

Usage:
    python3 monitor.py --rg rg-memory-pressure-lab --prefix memlabapp --count 4
    python3 monitor.py --rg rg-memory-pressure-lab --prefix memlabapp --count 4 --watch 60
"""

import argparse
import csv
import datetime
import json
import subprocess
import sys
import time
from pathlib import Path

PLAN_METRICS = [
    "MemoryPercentage",
    "CpuPercentage",
    "HttpQueueLength",
    "DiskQueueLength",
]
APP_METRICS = [
    "AverageResponseTime",
    "Http5xx",
    "Http4xx",
    "Requests",
    "MemoryWorkingSet",
]

OUTPUT_PLAN = "metrics-plan.csv"
OUTPUT_APPS = "metrics-apps.csv"


def az(*args) -> dict | list:
    result = subprocess.run(
        ["az"] + list(args), capture_output=True, text=True, check=True
    )
    return json.loads(result.stdout)


def get_resource_id(resource_group: str, resource_type: str, name: str) -> str:
    resources = az(
        "resource",
        "list",
        "--resource-group",
        resource_group,
        "--resource-type",
        resource_type,
        "--query",
        "[?name=='{}'].id".format(name),
        "--output",
        "json",
    )
    if not resources:
        raise ValueError(f"Resource not found: {resource_type}/{name}")
    return resources[0]


def get_metric(resource_id: str, metric: str, interval: str = "PT1M") -> list[dict]:
    end = datetime.datetime.utcnow()
    start = end - datetime.timedelta(minutes=5)
    try:
        data = az(
            "monitor",
            "metrics",
            "list",
            "--resource",
            resource_id,
            "--metric",
            metric,
            "--interval",
            interval,
            "--start-time",
            start.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "--end-time",
            end.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "--output",
            "json",
        )
        rows = []
        for series in data.get("value", []):
            for ts_data in series.get("timeseries", []):
                for point in ts_data.get("data", []):
                    value = (
                        point.get("average")
                        or point.get("total")
                        or point.get("maximum")
                        or 0.0
                    )
                    rows.append(
                        {
                            "ts": point.get("timeStamp", ""),
                            "metric": metric,
                            "value": round(value, 4),
                        }
                    )
        return rows
    except subprocess.CalledProcessError:
        return []


def collect_plan_metrics(
    resource_group: str, plan_name: str, writer: csv.DictWriter, snap_ts: str
):
    resource_id = get_resource_id(
        resource_group, "Microsoft.Web/serverfarms", plan_name
    )
    for metric in PLAN_METRICS:
        rows = get_metric(resource_id, metric)
        for row in rows:
            writer.writerow(
                {
                    "snap_ts": snap_ts,
                    "resource": plan_name,
                    "resource_type": "plan",
                    "metric": row["metric"],
                    "metric_ts": row["ts"],
                    "value": row["value"],
                }
            )


def collect_app_metrics(
    resource_group: str, app_names: list[str], writer: csv.DictWriter, snap_ts: str
):
    for app_name in app_names:
        resource_id = get_resource_id(resource_group, "Microsoft.Web/sites", app_name)
        for metric in APP_METRICS:
            rows = get_metric(resource_id, metric)
            for row in rows:
                writer.writerow(
                    {
                        "snap_ts": snap_ts,
                        "resource": app_name,
                        "resource_type": "app",
                        "metric": row["metric"],
                        "metric_ts": row["ts"],
                        "value": row["value"],
                    }
                )


def list_apps(resource_group: str, prefix: str, count: int) -> list[str]:
    apps = az(
        "webapp",
        "list",
        "--resource-group",
        resource_group,
        "--query",
        "[?starts_with(name, '{}')].name".format(prefix),
        "--output",
        "json",
    )
    return apps[:count]


def run_once(resource_group: str, prefix: str, app_count: int, output: str):
    plan_name = f"{prefix}-plan"
    app_names = list_apps(resource_group, prefix, app_count)
    snap_ts = datetime.datetime.utcnow().isoformat() + "Z"

    fieldnames = [
        "snap_ts",
        "resource",
        "resource_type",
        "metric",
        "metric_ts",
        "value",
    ]
    write_header = not Path(output).exists()

    with open(output, "a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        if write_header:
            writer.writeheader()

        print(f"[{snap_ts}] Collecting plan metrics: {plan_name}")
        collect_plan_metrics(resource_group, plan_name, writer, snap_ts)

        print(f"[{snap_ts}] Collecting app metrics: {app_names}")
        collect_app_metrics(resource_group, app_names, writer, snap_ts)

    print(f"  Written to {output}")


def main():
    parser = argparse.ArgumentParser(
        description="Memory pressure lab - Azure metrics collector"
    )
    parser.add_argument("--rg", required=True, help="Azure resource group name")
    parser.add_argument("--prefix", default="memlabapp", help="App name prefix")
    parser.add_argument(
        "--count", type=int, default=10, help="Max number of apps to monitor"
    )
    parser.add_argument("--output", default="metrics.csv", help="CSV output file")
    parser.add_argument(
        "--watch", type=int, default=0, help="Repeat every N seconds (0 = run once)"
    )
    args = parser.parse_args()

    if args.watch > 0:
        print(f"Watching every {args.watch}s. Ctrl+C to stop.")
        try:
            while True:
                run_once(args.rg, args.prefix, args.count, args.output)
                time.sleep(args.watch)
        except KeyboardInterrupt:
            print("\nStopped.")
    else:
        run_once(args.rg, args.prefix, args.count, args.output)


if __name__ == "__main__":
    main()
