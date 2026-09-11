#!/usr/bin/env bash
# perch-diag-hypervisor.sh — Perch diagnostics, HYPERVISOR ONLY.
#
# Run ON each hypervisor Morpheus manages, and only if you are using Perch's
# host-telemetry layers:
#   chmod +x perch-diag-hypervisor.sh && ./perch-diag-hypervisor.sh
#
# Writes /tmp/perch-diag-host-<host>-<date>.txt — attach that file to your issue.
#
# SAFETY: read-only. It runs exactly the four commands Perch runs, plus the
# checks that explain why one of them might not work. It changes nothing: no
# domain is started, stopped or edited, no flow is added or removed, no path is
# reconfigured.
#
# REVIEW BEFORE SENDING. The output describes this host: hostname, IP addresses,
# MAC addresses, domain names, bridge names, iSCSI portals and LUN identifiers.
# A public issue tracker is public — redact anything you would not post.

set -uo pipefail
OUT="/tmp/perch-diag-host-$(hostname -s)-$(date +%Y%m%d-%H%M).txt"

# Perch runs as the Morpheus agent's user and escalates with sudo where the
# agent's grant requires it. Run this script the same way you expect Perch to
# reach the host, and it will report which of the two paths works.
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi

section() { printf '\n\n=== %s ===\n' "$1" >>"$OUT"; }

# Run a command, capturing stdout+stderr and the exit status, without letting a
# missing binary or a refused escalation stop the script. A command that FAILED
# is a finding, not an error — which is why nothing here is fatal.
run() {
    local label="$1"; shift
    printf '\n--- %s\n$ %s\n' "$label" "$*" >>"$OUT"
    if ! command -v "${1#sudo}" >/dev/null 2>&1 && [ "$1" != "sudo" ]; then
        echo "[NOT INSTALLED] $1 is not on PATH" >>"$OUT"
        return
    fi
    "$@" >>"$OUT" 2>&1
    local rc=$?
    [ $rc -ne 0 ] && echo "[EXIT $rc]" >>"$OUT"
    return 0
}

: >"$OUT"
{
    echo "Perch hypervisor diagnostics"
    echo "host:      $(hostname -f 2>/dev/null || hostname)"
    echo "date:      $(date -Is)"
    echo "user:      $(id -un) (uid $(id -u))"
    echo "escalation: ${SUDO:-none needed (running as root)}"
} >>"$OUT"

# -----------------------------------------------------------------------------
section "1. Host identity and OS"
run "os release"      cat /etc/os-release
run "kernel"          uname -a
run "uptime"          uptime

# -----------------------------------------------------------------------------
# THE MOST IMPORTANT SECTION. Perch's host telemetry assumes libvirt + Open
# vSwitch. On VMware, Nutanix, Hyper-V or Linux-bridge KVM these layers cannot
# work as built — that is a limitation to report, not a bug to debug.
section "2. Is this stack supported? (libvirt + Open vSwitch)"
{
    for b in virsh ovs-appctl ovs-vsctl multipath iscsiadm; do
        p=$(command -v "$b" 2>/dev/null) && echo "FOUND    $b -> $p" || echo "MISSING  $b"
    done
    echo
    if command -v virsh >/dev/null 2>&1; then
        echo "libvirt: present"
    else
        echo "libvirt: ABSENT — 'Host Traffic Volume' cannot work on this host."
    fi
    if command -v ovs-appctl >/dev/null 2>&1; then
        echo "Open vSwitch: present"
    else
        echo "Open vSwitch: ABSENT — 'Active Host Flows' and 'Tracked Connections'"
        echo "  cannot work on this host. If this is a Linux-bridge KVM host, that"
        echo "  is expected and is a known limitation."
    fi
} >>"$OUT"

run "libvirt service" systemctl status libvirtd --no-pager
run "ovs service"     systemctl status openvswitch-switch --no-pager

# -----------------------------------------------------------------------------
section "3. Privilege — can the agent user escalate?"
{
    echo "Perch executes as the Morpheus agent's user, not as root. On a default"
    echo "agent install that account already holds an unrestricted NOPASSWD grant."
    echo "Where that grant has been narrowed, a scoped sudoers entry is needed —"
    echo "see docs/INSTALL.md."
    echo
} >>"$OUT"
run "sudo -n true"    $SUDO true
run "sudoers for morpheus-node" $SUDO sudo -l -U morpheus-node

# -----------------------------------------------------------------------------
section "4. Host Traffic Volume — virsh domstats --interface"
run "domain list"     $SUDO virsh list --all
run "domstats"        $SUDO virsh domstats --interface

# -----------------------------------------------------------------------------
section "5. Active Host Flows — ovs-appctl dpctl/dump-flows"
run "ovs bridges"     $SUDO ovs-vsctl show
run "dump-flows"      $SUDO ovs-appctl dpctl/dump-flows

# -----------------------------------------------------------------------------
section "6. Tracked Connections — ovs-appctl dpctl/dump-conntrack"
run "dump-conntrack"  $SUDO ovs-appctl dpctl/dump-conntrack

# -----------------------------------------------------------------------------
section "7. Storage Paths — multipath and iSCSI"
run "multipath"       $SUDO multipath -ll
run "iscsi sessions"  $SUDO iscsiadm -m session

# -----------------------------------------------------------------------------
# THREE FACTS, THREE LINES — and the separation is the point.
#
# "The LLDP layer is empty" has three completely different causes, and a single
# combined capture makes them indistinguishable:
#
#   lldpctl not on PATH   -> the package is not installed
#   unprivileged returns  -> would mean no sudo needed (it never does here)
#   sudo -n returns       -> working; empty output means the wire is quiet
#
# lldpd's control socket is /run/lldpd.socket and is ROOT-ONLY. /run/lldpd/ is
# the chroot and holds only etc/. There is no group-readable path to it, so a
# group grant is NOT an alternative and none is documented.
section "7b. LLDP neighbours — three separate captures"
{
    echo "The LLDP layer needs the lldpd package on each hypervisor. HPE does"
    echo "not install it by default. The three captures below distinguish 'not"
    echo "installed' from 'cannot escalate' from 'installed, running, and the"
    echo "wire is quiet' — which are three different instructions."
    echo
} >>"$OUT"

printf '\n--- (1) is lldpctl installed and on PATH?\n$ command -v lldpctl\n' >>"$OUT"
command -v lldpctl >>"$OUT" 2>&1 || echo "[NOT FOUND] lldpd is not installed — the LLDP layer cannot work on this host" >>"$OUT"

printf '\n--- (2) UNPRIVILEGED read (expected to fail — the socket is root-only)\n$ lldpctl -f keyvalue\n' >>"$OUT"
lldpctl -f keyvalue >>"$OUT" 2>&1
printf '[exit %s]\n' "$?" >>"$OUT"

printf '\n--- (3) PRIVILEGED read — this is the one Perch uses\n$ %s lldpctl -f keyvalue\n' "${SUDO:-}" >>"$OUT"
$SUDO lldpctl -f keyvalue >>"$OUT" 2>&1
printf '[exit %s]\n' "$?" >>"$OUT"

# Receive-only is a DAEMON_ARGS setting, not a runtime directive: `configure
# lldp status rx-only` returns rc=0 and silently does nothing. Config fields
# lie; counters do not, so capture both and let the counters settle it.
printf '\n--- (4) is this host ADVERTISING itself? (tx counters must be 0 if rx-only)\n' >>"$OUT"
run "daemon args" cat /etc/default/lldpd
run "statistics"  $SUDO lldpcli show statistics

# -----------------------------------------------------------------------------
# The commonest question about the flow layer, answered rather than guessed at.
section "8. Why might the flow layer be empty?"
{
    echo "Perch's 'Active Host Flows' layer draws guest-to-guest traffic observed"
    echo "in the OVS datapath ON THIS HOST."
    echo
    echo "It is empty, correctly, when:"
    echo "  - no VM on this host talks directly to another VM on this host;"
    echo "  - all guest traffic leaves via the gateway (very common);"
    echo "  - flows fall below the minimum-bytes noise filter;"
    echo "  - the datapath cache has aged out since the last conversation."
    echo
    echo "Section 5 above is the raw dump. If it is empty there, it is empty in"
    echo "Perch, and that is a fact about your traffic rather than a fault."
    echo
    echo "To see guest-to-gateway traffic instead, enable the external-flow"
    echo "option for that layer."
} >>"$OUT"

# -----------------------------------------------------------------------------
section "9. Interfaces and bridges"
run "addresses"       ip -br addr
run "links"           ip -br link

printf '\n\n=== collection complete ===\n' >>"$OUT"

echo "Wrote $OUT"
echo
echo "REVIEW IT BEFORE SENDING — it contains hostnames, IPs, MACs, domain names"
echo "and storage identifiers for this host."
