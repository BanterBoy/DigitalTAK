#!/usr/bin/env bash
# =============================================================================
# tak-uninstall.sh — Remove TAK Server 5.7 and all associated components
# =============================================================================
# Removes:
#   - TAK Server systemd service + RPM
#   - PostgreSQL service + data directory (/var/lib/pgsql)
#   - TAK installation directory (/opt/tak)
#   - TAK firewall rules (8089, 8443, 8446, 9091)
#   - SELinux policy module for takserver
#   - ulimit configuration (/etc/security/limits.conf entries)
#   - Openfire XMPP server (if installed)
#
# Does NOT remove:
#   - Java (system-wide, may be used by other applications)
#   - Rocky Linux OS configuration
#   - The SSH user account
#
# Usage:
#   sudo ./tak-uninstall.sh          # interactive (confirm before each step)
#   sudo ./tak-uninstall.sh --yes    # non-interactive (skip all confirmations)
#
# This script is idempotent — re-running after a clean uninstall is safe.
# =============================================================================

set -euo pipefail

# ── Privilege check ───────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)." >&2
    exit 1
fi

# ── Argument handling ─────────────────────────────────────────────────────────
YES_FLAG=false
for arg in "$@"; do
    case "$arg" in
        --yes|-y) YES_FLAG=true ;;
    esac
done

# ── Helper: confirm before proceeding ────────────────────────────────────────
confirm() {
    local prompt="$1"
    if [ "$YES_FLAG" = "true" ]; then
        echo "[auto-yes] $prompt"
        return 0
    fi
    read -r -p "$prompt [y/N] " reply
    case "$reply" in
        [Yy]*) return 0 ;;
        *) echo "Skipped." ; return 1 ;;
    esac
}

echo ""
echo "================================================================"
echo "  tak-uninstall.sh — TAK Server 5.7 Removal"
echo "================================================================"
echo ""
echo "  This will remove TAK Server, PostgreSQL data, certificates,"
echo "  firewall rules, and the SELinux policy module."
echo ""

if ! confirm "Proceed with uninstall?"; then
    echo "Aborted."
    exit 0
fi

# ── Step 1: Stop and disable TAK Server ──────────────────────────────────────
echo ""
echo "── Step 1: Stopping TAK Server ──"

if systemctl is-active takserver &>/dev/null; then
    systemctl stop takserver
    echo "  [OK] takserver stopped"
else
    echo "  takserver not running"
fi

if systemctl is-enabled takserver &>/dev/null; then
    systemctl disable takserver
    echo "  [OK] takserver disabled"
fi

# ── Step 2: Remove TAK Server RPM ────────────────────────────────────────────
echo ""
echo "── Step 2: Removing TAK Server RPM ──"

if rpm -q takserver &>/dev/null; then
    yum remove -y takserver
    echo "  [OK] takserver RPM removed"
else
    echo "  takserver RPM not installed"
fi

# ── Step 3: Remove /opt/tak ───────────────────────────────────────────────────
echo ""
echo "── Step 3: Removing /opt/tak ──"

if [ -d /opt/tak ]; then
    rm -rf /opt/tak
    echo "  [OK] /opt/tak removed"
else
    echo "  /opt/tak not found"
fi

# ── Step 4: Stop and remove PostgreSQL ───────────────────────────────────────
echo ""
echo "── Step 4: Removing PostgreSQL ──"

# Find the versioned PostgreSQL service name (e.g. postgresql-15)
PG_SERVICE=$(systemctl list-units --type=service --all 2>/dev/null \
    | grep -oP 'postgresql-\S+\.service' | head -1 | sed 's/\.service//' || true)

if [ -n "$PG_SERVICE" ]; then
    if systemctl is-active "$PG_SERVICE" &>/dev/null; then
        systemctl stop "$PG_SERVICE"
        echo "  [OK] $PG_SERVICE stopped"
    fi
    if systemctl is-enabled "$PG_SERVICE" &>/dev/null; then
        systemctl disable "$PG_SERVICE"
    fi
fi

# Remove PostgreSQL packages
PG_PKGS=$(rpm -qa 'postgresql*' 2>/dev/null || true)
if [ -n "$PG_PKGS" ]; then
    # shellcheck disable=SC2086
    yum remove -y $PG_PKGS
    echo "  [OK] PostgreSQL packages removed"
else
    echo "  No PostgreSQL packages found"
fi

# Remove PostgreSQL data directories
for pg_dir in /var/lib/pgsql /var/lib/postgresql; do
    if [ -d "$pg_dir" ]; then
        rm -rf "$pg_dir"
        echo "  [OK] Removed $pg_dir"
    fi
done

# ── Step 5: Remove Openfire (if installed) ────────────────────────────────────
echo ""
echo "── Step 5: Removing Openfire (if installed) ──"

if systemctl is-active openfire &>/dev/null; then
    systemctl stop openfire
    echo "  [OK] openfire stopped"
fi

if rpm -q openfire &>/dev/null; then
    yum remove -y openfire
    echo "  [OK] openfire RPM removed"
else
    echo "  openfire not installed"
fi

for of_dir in /opt/openfire /var/lib/openfire; do
    if [ -d "$of_dir" ]; then
        rm -rf "$of_dir"
        echo "  [OK] Removed $of_dir"
    fi
done

# ── Step 6: Remove firewall rules ────────────────────────────────────────────
echo ""
echo "── Step 6: Removing TAK firewall rules ──"

if systemctl is-active firewalld &>/dev/null; then
    for port in 8089/tcp 8443/tcp 8446/tcp 9091/tcp; do
        if firewall-cmd --query-port="$port" --permanent &>/dev/null; then
            firewall-cmd --permanent --remove-port="$port" &>/dev/null
            echo "  [OK] Removed firewall rule: $port"
        fi
    done
    firewall-cmd --reload &>/dev/null
    echo "  [OK] Firewall reloaded"
else
    echo "  firewalld not running — skipping"
fi

# ── Step 7: Remove SELinux policy module ─────────────────────────────────────
echo ""
echo "── Step 7: Removing SELinux takserver module ──"

if semodule -l 2>/dev/null | grep -q takserver; then
    semodule -r takserver
    echo "  [OK] SELinux takserver module removed"
else
    echo "  takserver SELinux module not installed"
fi

# ── Step 8: Remove ulimit configuration ──────────────────────────────────────
echo ""
echo "── Step 8: Removing ulimit configuration ──"

if grep -q "nofile 32768" /etc/security/limits.conf 2>/dev/null; then
    sed -i '/nofile 32768/d' /etc/security/limits.conf
    echo "  [OK] Removed nofile 32768 from /etc/security/limits.conf"
else
    echo "  No TAK ulimit entries found"
fi

# Remove any TAK-specific limits drop-in file
if [ -f /etc/security/limits.d/takserver.conf ]; then
    rm -f /etc/security/limits.d/takserver.conf
    echo "  [OK] Removed /etc/security/limits.d/takserver.conf"
fi

# ── Step 9: Remove TAK yum repository ────────────────────────────────────────
echo ""
echo "── Step 9: Removing TAK yum repositories ──"

for repo_file in /etc/yum.repos.d/takserver*.repo; do
    if [ -f "$repo_file" ]; then
        rm -f "$repo_file"
        echo "  [OK] Removed $repo_file"
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  tak-uninstall.sh complete."
echo ""
echo "  Removed:"
echo "    - TAK Server RPM and /opt/tak"
echo "    - PostgreSQL packages and data"
echo "    - Openfire (if installed)"
echo "    - Firewall rules for TAK ports"
echo "    - SELinux takserver policy module"
echo "    - ulimit configuration"
echo ""
echo "  NOT removed (shared/system components):"
echo "    - Java (use 'sudo yum remove java-17*' if desired)"
echo "    - SSH user account and home directory"
echo "    - OS locale and network configuration"
echo "================================================================"
echo ""
