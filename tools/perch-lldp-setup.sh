#!/usr/bin/env bash
#
# perch-lldp-setup.sh — install and configure lldpd on a Morpheus MVM hypervisor,
#                       then capture everything Perch's LLDP layer needs to see.
#
#   sudo ./perch-lldp-setup.sh
#
# Writes /tmp/perch-lldp-<host>-<timestamp>.txt
#
# WHAT IT CHANGES ON THE HOST
#   - installs the lldpd package  (only if the candidate comes from HPE's mirror)
#   - sets DAEMON_ARGS="-c -r" in /etc/default/lldpd
#         -r  receive-only: the host listens and never advertises itself
#         -c  also receive CDP (Cisco access ports often run CDP, not LLDP)
#   - enables and starts lldpd.service
#
# WHAT IT DOES NOT DO
#   - does not add, remove or modify any apt repository
#   - does not upgrade, remove or autoremove any package
#   - does not touch libvirt, OVS, Ceph or networking config
#   - every diagnostic read is read-only
#
# IT WILL REFUSE TO INSTALL if lldpd's candidate version does not come from
# HPE's own mirror. That guard is deliberate: on a host with a different repo
# set, silently pulling lldpd from elsewhere is exactly the outcome we ruled out.
#
# Re-running is safe. If lldpd is already installed it skips to configuration.
#
set -uo pipefail

STAMP=$(date +%Y%m%d-%H%M%S)
HOST=$(hostname -s)
OUT="/tmp/perch-lldp-${HOST}-${STAMP}.txt"
HPE_MIRROR="update1.linux.hpe.com"

exec > >(tee "$OUT") 2>&1

hr()  { echo; echo "=============================================================="; }
sec() { hr; echo "== $*"; echo "=============================================================="; }

sec "PERCH LLDP SETUP — $HOST — $(date -Is)"

if [ "$(id -u)" -ne 0 ]; then
    echo "FATAL: must run as root (sudo)."
    exit 1
fi

# ---------------------------------------------------------------- 0. preflight
sec "0. PREFLIGHT"
grep PRETTY_NAME /etc/os-release
echo "arch:     $(dpkg --print-architecture)"
echo "kernel:   $(uname -r)"
echo "uptime:   $(uptime -p)"
echo
echo "--- configured apt sources ---"
ls -la /etc/apt/sources.list.d/
echo
echo "--- apt preferences (should be empty) ---"
ls -la /etc/apt/preferences.d/ 2>/dev/null

# ---------------------------------------------------------------- 1. backup
sec "1. BACKUP"
tar czf "/root/apt-backup-${STAMP}.tar.gz" /etc/apt 2>/dev/null \
    && echo "apt config  -> /root/apt-backup-${STAMP}.tar.gz"
dpkg -l > "/root/dpkg-list-before-${STAMP}.txt" \
    && echo "package list-> /root/dpkg-list-before-${STAMP}.txt"
if [ -f /etc/default/lldpd ]; then
    cp -a /etc/default/lldpd "/root/lldpd-default-before-${STAMP}"
    echo "existing /etc/default/lldpd -> /root/lldpd-default-before-${STAMP}"
fi
echo
echo "RESTORE POINT: ${STAMP}"

# ---------------------------------------------------------------- 2. source guard
sec "2. PACKAGE SOURCE CHECK"
apt-cache policy lldpd

ALREADY_INSTALLED=no
if dpkg -l lldpd 2>/dev/null | grep -q '^ii'; then
    ALREADY_INSTALLED=yes
    echo
    echo "lldpd is already installed — skipping install, proceeding to configure."
fi

if [ "$ALREADY_INSTALLED" = "no" ]; then
    CAND=$(apt-cache policy lldpd | awk '/Candidate:/{print $2}')
    if [ -z "$CAND" ] || [ "$CAND" = "(none)" ]; then
        echo
        echo "FATAL: no candidate version of lldpd is available on this host."
        echo "       This host's repo set differs from the reference host."
        echo "       Send section 0 and 2 of this file. Stopping — nothing changed."
        exit 2
    fi

    # The 500-priority line must reference HPE's mirror.
    if ! apt-cache policy lldpd | grep -E '^\s+500\s' | grep -q "$HPE_MIRROR"; then
        echo
        echo "FATAL: lldpd candidate ${CAND} is NOT served at priority 500 from"
        echo "       ${HPE_MIRROR}. Refusing to install from an unexpected source."
        echo "       Send section 2 of this file. Stopping — nothing changed."
        exit 3
    fi
    echo
    echo "OK: candidate ${CAND} comes from HPE's mirror. Proceeding."

    # ------------------------------------------------------------ 3. dry run
    sec "3. INSTALL DRY RUN"
    apt-get install -s --no-install-recommends lldpd

    echo
    echo "--- plan check ---"
    PLAN=$(apt-get install -s --no-install-recommends lldpd 2>&1)
    # Only the action lines matter. apt's "no longer required" notice is not a plan.
    BAD=$(echo "$PLAN" | grep -E '^(Inst|Conf|Remv)' \
                        | grep -iE 'ceph|libvirt|qemu|openvswitch|linux-image|linux-modules')
    UPG=$(echo "$PLAN" | grep -E '^[0-9]+ upgraded' | awk '{print $1}')

    if [ -n "$BAD" ]; then
        echo "FATAL: install plan touches infrastructure packages:"
        echo "$BAD"
        echo "Stopping — nothing changed."
        exit 4
    fi
    if [ "${UPG:-0}" != "0" ]; then
        echo "FATAL: install plan would upgrade ${UPG} package(s). Expected 0."
        echo "Stopping — nothing changed."
        exit 5
    fi
    echo "OK: plan installs new packages only, upgrades nothing."

    # ------------------------------------------------------------ 4. install
    sec "4. INSTALL"
    apt-get install -y --no-install-recommends lldpd
    RC=$?
    if [ $RC -ne 0 ]; then
        echo "FATAL: apt-get install failed with rc=${RC}. Stopping."
        exit 6
    fi
fi

echo
dpkg -l lldpd | tail -1
command -v lldpctl lldpcli

# ---------------------------------------------------------------- 5. configure
sec "5. CONFIGURE — receive-only + CDP"
# VERIFIED on four hosts: the runtime directive `configure lldp status rx-only`
# returns rc=0 and SILENTLY DOES NOTHING. The daemon flag -r is what works.
# Remove the config file if an earlier run of this script wrote one.
rm -f /etc/lldpd.d/50-perch.conf

if grep -q '^DAEMON_ARGS=' /etc/default/lldpd 2>/dev/null; then
    sed -i 's/^DAEMON_ARGS=.*/DAEMON_ARGS="-c -r"/' /etc/default/lldpd
else
    echo 'DAEMON_ARGS="-c -r"' >> /etc/default/lldpd
fi
echo
echo "/etc/default/lldpd:"
grep -v '^\s*#' /etc/default/lldpd | grep -v '^\s*$'

systemctl enable lldpd  >/dev/null 2>&1
systemctl restart lldpd
sleep 3
systemctl status lldpd --no-pager -o cat | head -14

# ---------------------------------------------------------------- 6. rx-only
sec "6. RECEIVE-ONLY VERIFICATION"
echo "--- configuration ---"
lldpcli show configuration | grep -iE 'receive mode|transmit'
echo
echo "'Receive mode: yes' => receive-only is in effect."
echo
echo "--- transmit counters, measured over 60s ---"
echo "Config fields can be wrong. Counters cannot. If any counter below moves,"
echo "this host IS advertising itself on your network."
lldpcli show statistics | grep -A1 'Interface:' | grep -iE 'Interface|Transmitted' \
    > /tmp/perch-tx-before.$$
sleep 60
lldpcli show statistics | grep -A1 'Interface:' | grep -iE 'Interface|Transmitted' \
    > /tmp/perch-tx-after.$$
if diff -q /tmp/perch-tx-before.$$ /tmp/perch-tx-after.$$ >/dev/null; then
    echo "SILENT: no transmitted frames on any interface across 60s."
else
    echo "TRANSMITTING: counters moved. -r is not in effect on this build."
    diff /tmp/perch-tx-before.$$ /tmp/perch-tx-after.$$
fi
rm -f /tmp/perch-tx-before.$$ /tmp/perch-tx-after.$$

# ---------------------------------------------------------------- 7. neighbors
sec "7. LLDP NEIGHBORS"
echo "--- three separate captures. Three facts, three answers. ---"
echo "[a] is lldpctl on morpheus-node's PATH?"
sudo -u morpheus-node bash -c 'command -v lldpctl' 2>&1 || echo "  NOT ON PATH"
echo
echo "[b] unprivileged read (expected to FAIL — socket is root-only):"
sudo -u morpheus-node bash -c 'lldpctl -f keyvalue' 2>&1 | head -3
echo
echo "[c] sudo -n read (this is the path Perch uses):"
sudo -u morpheus-node bash -c 'sudo -n lldpctl -f keyvalue' 2>&1 | head -3
echo "    empty here => add the Cmnd_Alias from the spec, then re-run"
echo
echo "--- keyvalue as root (this is what Perch parses) ---"
lldpctl -f keyvalue
echo
echo "--- neighbor count ---"
lldpctl -f keyvalue | grep -c '\.chassis\.mac=' || true
echo
echo "--- distinct chassis ---"
lldpctl -f keyvalue | grep '\.chassis\.name=' | sed 's/^lldp\.//' | sort -u
echo
echo "--- human-readable, for eyeballing ---"
lldpctl | head -80

# ---------------------------------------------------------------- 8. local side
sec "8. LOCAL INTERFACES"
echo "--- ip -br link ---"
ip -br link
echo
echo "--- bonds ---"
for b in /proc/net/bonding/*; do
    [ -e "$b" ] || continue
    echo "### $b"
    grep -E 'Slave Interface|MII Status|Bonding Mode|Permanent HW' "$b"
done
echo
echo "--- OVS bridges and ports ---"
ovs-vsctl show 2>/dev/null | head -60
echo
echo "--- OVS interface count ---"
ovs-vsctl --columns=name list interface 2>/dev/null | grep -c '^name' || true

# ---------------------------------------------------------------- 9. domains
sec "9. LIBVIRT DOMAINS — managed vs unmanaged"
virsh list --all 2>/dev/null
echo
echo "--- interfaces per running domain ---"
for d in $(virsh list --name 2>/dev/null); do
    echo "### $d"
    virsh domiflist "$d" 2>/dev/null
done
echo
echo "NOTE: compare this list against what Morpheus shows for this host."
echo "      A domain here that Morpheus does not know about is invisible to"
echo "      Perch — Perch renders the managed estate, not the hypervisor's."

# ---------------------------------------------------------------- 10. summary
sec "10. SUMMARY"
echo "host:            $HOST"
echo "restore point:   $STAMP"
echo "lldpd:           $(dpkg -l lldpd 2>/dev/null | awk '/^ii/{print $3}')"
echo "service:         $(systemctl is-active lldpd)"
echo "rx-only:         $(lldpcli show configuration | awk -F': ' '/Receive mode/{print $2}')"
echo "neighbors:       $(lldpctl -f keyvalue | grep -c '\.chassis\.mac=')"
echo "distinct switch: $(lldpctl -f keyvalue | grep '\.chassis\.mac=' | cut -d= -f2 | sort -u | wc -l)"
echo "libvirt domains: $(virsh list --all 2>/dev/null | tail -n +3 | grep -c '[a-z]')"
echo "OVS interfaces:  $(ovs-vsctl --columns=name list interface 2>/dev/null | grep -c '^name')"
echo
echo "output written to: $OUT"

sec "END — $(date -Is)"
