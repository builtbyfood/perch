#!/usr/bin/env bash
# perch-diag-appliance.sh — Perch diagnostics, APPLIANCE ONLY.
#
# Run ON the Morpheus appliance (the machine serving the UI):
#   chmod +x perch-diag-appliance.sh && sudo ./perch-diag-appliance.sh
#
# Writes /tmp/perch-diag-appliance-<host>-<date>.txt — attach that file to your
# issue.
#
# SAFETY: read-only. It selects no credential-bearing column (config,
# ssh_password, raw_data, last_stats, service_password).
#
# REVIEW BEFORE SENDING. The output describes your estate: hostnames, IP
# addresses, cloud/server/network names, MAC addresses and counts. A public
# issue tracker is public — redact anything you would not post.

set -uo pipefail
OUT="/tmp/perch-diag-appliance-$(hostname -s)-$(date +%Y%m%d-%H%M).txt"
MYSQL=""
LOG="/var/log/morpheus/morpheus-ui/current"
SECRETS="/etc/morpheus/morpheus-secrets.json"

# Strip ANSI, collapse runs of identical messages (keeping a count).
# Strip ANSI + log timestamps, then collapse duplicate messages ANYWHERE in the
# section (not just adjacent ones). v2 only collapsed runs, and the resolver
# messages interleave, so hundreds of near-identical lines still got through.
# Strip ANSI + the outer log timestamp, then collapse duplicate messages anywhere
# in the section. v3 keyed on the wrong substring — the logger separator in this
# log is " - " with no bracket before it, so nothing was stripped, every line
# looked unique unless it shared a millisecond, and only the END summary survived
# the tail. Take everything after the FIRST " - ": the prefix never contains one,
# so this drops timestamp, thread and logger in one step.
clean() {
  sed -E 's/\x1b\[[0-9;]*[mK]//g' \
  | sed -E "s/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+ +//; s/^'+//" \
  | awk '{
      msg = $0
      i = index(msg, " - ")
      if (i > 0) msg = substr(msg, i + 3)
      if (seen[msg]++ == 0) { print; order[++k] = msg }
      else dup[msg]++
    }
    END {
      shown = 0
      for (i = 1; i <= k; i++) {
        m = order[i]
        if (dup[m] > 0) {
          if (!shown) { print ""; print "  --- repeats suppressed (first occurrence shown above) ---"; shown = 1 }
          printf "  %5d more: %s\n", dup[m], substr(m, 1, 100)
        }
      }
    }'
}

exec > >(tee "$OUT") 2>&1
echo "=== Perch appliance diagnostics v4 — $(date -Is) — $(hostname -f) ==="

sec() { echo; echo "──────── $* ────────"; }

sec "1. Morpheus and OS"
grep -E '^(NAME|VERSION)=' /etc/os-release 2>/dev/null
echo "kernel: $(uname -r)"
for f in /etc/morpheus/morpheus-version /opt/morpheus/embedded/VERSION; do
  [ -r "$f" ] && echo "morpheus ($f): $(cat "$f")"
done
# The version is in the log banner on every restart even when no version file exists.
echo "morpheus (log banner): $(sudo grep -ohE 'Morpheus[ |]+[0-9]+\.[0-9]+\.[0-9]+' "$LOG" 2>/dev/null | tail -1)"
echo "java: $(java -version 2>&1 | head -1 || true)"
echo "  (java missing from PATH is normal — Morpheus bundles its own JRE)"

sec "2. Perch plugin — loaded version, and any stale jars"
echo "--- most recent load lines ---"
sudo grep -hE 'Loading Plugin com\.morpheusdata\.perch' "$LOG" 2>/dev/null | clean | tail -5
echo
echo "--- surface registration (the authoritative list of what loaded) ---"
sudo grep -h 'perch-init' "$LOG" 2>/dev/null | clean | tail -4
echo
echo "--- jars on disk ---"
echo "ACTIVE (plugins/):"
sudo ls -1 /var/opt/morpheus/morpheus-ui/plugins/ 2>/dev/null | grep -i perch || echo "  none"
echo "DISABLED (disabled/):"
sudo ls -1 /var/opt/morpheus/morpheus-ui/disabled/ 2>/dev/null | grep -i perch || echo "  none"
ACTIVE_N=$(sudo ls -1 /var/opt/morpheus/morpheus-ui/plugins/ 2>/dev/null | grep -ci perch || true)
if [ "${ACTIVE_N:-0}" -gt 1 ]; then
  echo
  echo "  *** ${ACTIVE_N} Perch jars are in the ACTIVE plugins directory. ***"
  echo "  Only the version named in the load line above is running. The others are"
  echo "  stale uploads. If behaviour does not match the version you think you"
  echo "  installed, this is the first thing to check."
fi

sec "3. Perch log — last 400 lines, de-duplicated"
sudo grep -hE '\[perch|c\.m\.p\.' "$LOG" 2>/dev/null | tail -400 | clean

sec "4. Collector status summary — what each layer reported"
echo "nodes/edges per layer, plus [status, findings]. status != ok is the thing to read."
sudo grep -ohE '\[topology\] [a-z-]+: [0-9]+ nodes, [0-9]+ edges .*' "$LOG" 2>/dev/null \
  | sed -E 's/\x1b\[[0-9;]*[mK]//g' | tail -40

sec "5. Why phases were skipped — which gate refused"
sudo grep -ohE 'skipping collector [a-z-]+ — .*' "$LOG" 2>/dev/null \
  | sed -E 's/\x1b\[[0-9;]*[mK]//g' | sort -u

sec "6. SCHEMA DRIFT — the single most useful section"
echo "Tables/columns Perch expected that your Morpheus does not have."
sudo grep -hiE 'schema drift|Unknown column|doesn.t exist' "$LOG" 2>/dev/null | clean | tail -30

sec "7. Raw report options actually submitted"
sudo grep -hA22 'raw configMap' "$LOG" 2>/dev/null | clean | tail -28

sec "8. Host command / telemetry attempts"
echo "outcome=OK privileged=true means sudo -n was used; privileged=false means the"
echo "agent could run it directly. bytes= is how much the host returned — a tiny"
echo "byte count with outcome=OK means the command ran and had little to say."
sudo grep -hE '\[host-cmd\]|outcome=' "$LOG" 2>/dev/null | clean | tail -40

sec "9. Errors and stack traces"
sudo grep -hiE 'exception|error|timeout|deadlock|OutOfMemory' "$LOG" 2>/dev/null \
  | grep -iE 'perch|c\.m\.p\.|PluginManager' | clean | tail -25

sec "10. Database"
# v1 assumed the password sat within 3 lines of "mysql" and used a fixed key name.
# Try several extractions, then several client paths.
for c in /opt/morpheus/embedded/mysql/bin/mysql /usr/bin/mysql /usr/bin/mariadb; do
  [ -x "$c" ] && MYSQL="$c" && break
done

# v2 found a password but the wrong one — 'mysql' holds more than one
# password-ish key on some builds (a root one and a morpheus one), and taking
# the first match produced ERROR 1045. Collect ALL candidates and try each.
CANDS=""
if sudo test -r "$SECRETS" 2>/dev/null; then
  if command -v python3 >/dev/null 2>&1; then
    CANDS=$(sudo cat "$SECRETS" 2>/dev/null | python3 -c '
import sys, json
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
out, seen = [], set()
def walk(o, ctx=""):
    if isinstance(o, dict):
        for k, v in o.items():
            if isinstance(v, str) and "pass" in k.lower():
                # prefer keys mentioning morpheus, then the mysql context
                rank = 0 if "morpheus" in k.lower() else (1 if "mysql" in ctx else 2)
                if v not in seen:
                    seen.add(v); out.append((rank, v))
            walk(v, ctx + " " + k.lower())
    elif isinstance(o, list):
        for v in o: walk(v, ctx)
walk(d)
for _, v in sorted(out, key=lambda t: t[0]): print(v)
' 2>/dev/null)
  fi
  if [ -z "$CANDS" ]; then
    CANDS=$(sudo grep -A25 -i '"mysql"' "$SECRETS" 2>/dev/null \
            | grep -oE '"[^"]*[Pp]ass[^"]*"[[:space:]]*:[[:space:]]*"[^"]+"' \
            | sed -E 's/.*:[[:space:]]*"([^"]+)"/\1/')
  fi
fi

QUERIES="$(dirname "$0")/perch-diag-queries.sql"
[ -r "$QUERIES" ] || QUERIES="./perch-diag-queries.sql"

if [ -z "$MYSQL" ]; then
  echo "SKIPPED: no mysql client found. If Morpheus uses an external database,"
  echo "run perch-diag-queries.sql by hand against it and send the output."
elif [ ! -r "$QUERIES" ]; then
  echo "SKIPPED: perch-diag-queries.sql not found next to this script."
  echo "Keep the two files together, or run the .sql by hand."
elif [ -z "$CANDS" ]; then
  echo "SKIPPED: no password candidates found in $SECRETS."
  echo "Password-like key names present (VALUES NOT SHOWN):"
  sudo grep -oE '"[a-zA-Z_]*[Pp]ass[a-zA-Z_]*"' "$SECRETS" 2>/dev/null | sort -u
  echo "Run this by hand and send the output:"
  echo "  $MYSQL -u morpheus -h 127.0.0.1 -p morpheus --force --table < perch-diag-queries.sql"
else
  N=0; OK=0
  while IFS= read -r pw; do
    [ -z "$pw" ] && continue
    N=$((N+1))
    if "$MYSQL" -u morpheus -h 127.0.0.1 -p"$pw" morpheus \
         -e "SELECT 1" >/dev/null 2>&1; then
      echo "(connected on candidate $N of $(echo "$CANDS" | grep -c .); using -h 127.0.0.1 —"
      echo " localhost would use the unix socket and be refused)"
      "$MYSQL" -u morpheus -h 127.0.0.1 -p"$pw" morpheus --force --table < "$QUERIES" 2>&1 \
        | grep -v "Using a password on the command line"
      OK=1; break
    fi
  done <<< "$CANDS"
  if [ "$OK" -eq 0 ]; then
    echo "SKIPPED: tried $N password candidate(s) from $SECRETS; none was accepted."
    echo "Password-like key names present (VALUES NOT SHOWN):"
    sudo grep -oE '"[a-zA-Z_]*[Pp]ass[a-zA-Z_]*"' "$SECRETS" 2>/dev/null | sort -u
    echo "Run this by hand and send the output:"
    echo "  $MYSQL -u morpheus -h 127.0.0.1 -p morpheus --force --table < perch-diag-queries.sql"
  fi
fi

sec "DONE"
echo "Output written to: $OUT"
echo
echo "REVIEW IT BEFORE SENDING — it contains hostnames, IPs, MACs and the names"
echo "of your clouds, servers and networks."
echo
echo "Please also send the browser console output and your answers to section 5"
echo "of docs/DIAGNOSTICS.md — the scripts cannot capture what looked wrong."
