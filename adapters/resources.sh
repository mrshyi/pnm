#!/usr/bin/env bash

# The directory argument is for private proc fixtures; CLI observations use /proc.
pnm_resource_observations() {
    command -v python3 >/dev/null 2>&1 || return "$PNM_EXIT_UNAVAILABLE"
    python3 - "${1:-/proc}" <<'PY'
import math
from pathlib import Path
import sys

root = Path(sys.argv[1])

def emit(name, status, summary, detail):
    print("|".join((name, status, summary, detail)))

try:
    memory = {}
    for line in (root / "meminfo").read_text().splitlines():
        fields = line.split()
        if fields[0] in ("MemTotal:", "MemAvailable:", "SwapTotal:", "SwapFree:"):
            if len(fields) != 3 or fields[2] != "kB" or not fields[1].isdigit():
                raise ValueError("invalid memory counter")
            memory[fields[0][:-1]] = int(fields[1])
except (OSError, ValueError, IndexError):
    memory = {}

for name, total_key, free_key in (("memory", "MemTotal", "MemAvailable"),
                                  ("swap", "SwapTotal", "SwapFree")):
    total, free = memory.get(total_key), memory.get(free_key)
    if total is None or free is None or free > total or (name == "memory" and total == 0):
        emit(name, "UNKNOWN", "Memory counters cannot be determined", "required proc counters are unavailable or invalid")
    elif total == 0:
        emit(name, "SKIP", "Swap is not configured", "0 KiB total")
    else:
        low = free * 10 < total
        emit(name, "WARN" if low else "OK", "Available memory" if name == "memory" else "Free swap",
             f"{free}/{total} KiB; {'below 10%' if low else 'at least 10%'} remaining")

try:
    loads = [float(value) for value in (root / "loadavg").read_text().split()[:3]]
    cpus = sum(line.split()[0][3:].isdigit() for line in (root / "stat").read_text().splitlines()
               if line.startswith("cpu") and line.split())
    if len(loads) != 3 or not all(math.isfinite(value) and value >= 0 for value in loads) or cpus == 0:
        raise ValueError("invalid load counters")
    emit("load", "WARN" if loads[2] > cpus else "OK", "System load averages",
         f"1/5/15 min: {loads[0]:g}/{loads[1]:g}/{loads[2]:g}; {cpus} visible logical CPUs; not CPU usage")
except (OSError, ValueError, IndexError):
    emit("load", "UNKNOWN", "System load cannot be determined", "required proc counters are unavailable or invalid")

try:
    counters = dict(line.split() for line in (root / "vmstat").read_text().splitlines())
    value = counters["oom_kill"]
    if not value.isdigit():
        raise ValueError("invalid OOM counter")
    count = int(value)
    emit("oom", "WARN" if count else "OK", "Kernel OOM kills since boot",
         f"{count}; cumulative system counter, not attributed to PNM")
except (OSError, ValueError, KeyError):
    emit("oom", "UNKNOWN", "Kernel OOM counter cannot be determined", "oom_kill is unavailable or invalid")
PY
}
