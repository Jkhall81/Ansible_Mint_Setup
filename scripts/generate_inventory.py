#!/usr/bin/env python3
"""
Generate an Ansible inventory file (hosts.ini) from hosts_ips.txt
created by the machine_setup.pl bootstrapper.
"""

import re
from pathlib import Path

# Paths
SAMBA_LOG = Path("/srv/samba/bootstrap/hosts_ips.txt")  # adjust if needed
OUTPUT_INVENTORY = Path("../inventory/hosts.ini")  # relative to scripts/

# Regex to capture IP and role
LINE_PATTERN = re.compile(
    r"(?P<ip>\d{1,3}(?:\.\d{1,3}){3})\/\d+.*ROLE=(?P<role>\w+)", re.IGNORECASE
)

# Buckets for each group
groups = {
    "training": [],
    "agent": [],
    "manager": []
}

print(f"[*] Reading from {SAMBA_LOG.resolve()}")

if not SAMBA_LOG.exists():
    print(f"[!] ERROR: {SAMBA_LOG} not found.")
    exit(1)

with SAMBA_LOG.open() as f:
    for line in f:
        match = LINE_PATTERN.search(line)
        if match:
            ip = match.group("ip")
            role = match.group("role").lower()
            if role in groups:
                groups[role].append(ip)
            else:
                print(f"[!] Unknown role '{role}' in line: {line.strip()}")
        else:
            print(f"[!] Could not parse line: {line.strip()}")

# Ensure the output folder exists
OUTPUT_INVENTORY.parent.mkdir(parents=True, exist_ok=True)

print(f"[*] Writing Ansible inventory to {OUTPUT_INVENTORY.resolve()}")

with OUTPUT_INVENTORY.open("w") as inv:
    inv.write("[training_machines]\n")
    inv.writelines(f"{ip}\n" for ip in groups["training"])
    inv.write("\n[agent_machines]\n")
    inv.writelines(f"{ip}\n" for ip in groups["agent"])
    inv.write("\n[manager_machines]\n")
    inv.writelines(f"{ip}\n" for ip in groups["manager"])

print("[+] Inventory file successfully generated!")
print("    └──", OUTPUT_INVENTORY.resolve())
print()
print("Preview:")
print("----------------------")
print(OUTPUT_INVENTORY.read_text())
print("----------------------")
