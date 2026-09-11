# Installing Perch

## Requirements

| | |
|---|---|
| Morpheus / HPE VM Essentials | **9.0.1 or later** |
| Browser | anything current; the graph is canvas-based |
| Permissions to view the report | `Operations: Reports` |
| Permissions to view the tabs | `Provisioning: Instances`, `Infrastructure: Hosts` |
| Host telemetry *(optional)* | Morpheus agent on each hypervisor, plus libvirt and Open vSwitch |

Perch declares a minimum appliance version of 9.0.1 and Morpheus enforces it at upload. Earlier versions are not supported — not as a policy, but because the plugin has never been run on one.

Perch is **read-only**. Installing it cannot change your estate.

---

## 1. Download

Get `perch-morpheus-plugin-<version>.jar` from the [Releases page](../../../releases).

Each release also publishes a `.sha256`. Verify before uploading:

```bash
sha256sum -c perch-morpheus-plugin-<version>.jar.sha256
```

The jar carries its own licence and third-party attribution at `META-INF/LICENSE` and `META-INF/NOTICE`, so it remains compliant if it travels away from this repository.

## 2. Upload

**Administration → Integrations → Plugins → Upload**, then select the jar.

Morpheus loads the plugin immediately. There is no appliance restart and no service to bounce.

## 3. Confirm it loaded

Three checks, cheapest first.

**The plugin list.** Administration → Integrations → Plugins should show **Perch**, enabled, with the version you just uploaded. If the version shown is older than the file you uploaded, the browser is serving a cached page — hard-refresh before believing it.

**The surfaces appear.**

- **Operations → Reports** offers *Perch — Your Morpheus Topology*.
- A **Topology** tab appears on instance, server, cluster and network detail pages.

**The assets actually loaded.** Open any surface, then the browser console (F12). Each Perch asset announces itself with the build it came from:

```
[perch-asset] perch.js build 0.3.86 loaded and executed to completion
[perch-asset] perch-layers.js build 0.3.86 loaded and executed to completion
[perch-asset] perch-resize.js build 0.3.86 loaded and executed to completion
[perch-asset] perch-search.js build 0.3.86 loaded and executed to completion
[perch-asset] perch-edge-labels.js build 0.3.86 loaded and executed to completion
```

**The version in those lines is the one actually running in the browser.** Morpheus caches plugin assets and browsers cache them again, so this is the only reliable way to tell a stale asset from a fix that did not work. If the build number is older than the jar you uploaded, hard-refresh; if it persists, the appliance is still serving the previous asset.

An absent line means that file never finished executing — see [Troubleshooting](TROUBLESHOOTING.md).

## 4. Run the report

**Operations → Reports → Perch — Your Morpheus Topology → Run Now.**

The options dialog lets you pick a cloud and choose which layers to collect for this run. Defaults are safe: everything that stays inside the Morpheus database is on, everything that leaves it is off.

---

## Host telemetry (optional)

Six layers read from the hypervisors themselves rather than the database:

| Layer | Command run on the host |
|---|---|
| Host Traffic Volume | `virsh domstats --interface` |
| Active Host Flows | `ovs-appctl dpctl/dump-flows` |
| Tracked Connections | `ovs-appctl dpctl/dump-conntrack` |
| Storage Paths | `multipath -ll`, `iscsiadm -m session` |
| LLDP Neighbours | `lldpctl -f keyvalue`, `ip -br link` |
| Observed passthrough *(devices extension)* | `virsh nodedev-dumpxml`, `virsh dumpxml` |

All are read-only, and all require **libvirt and Open vSwitch** on the host — on VMware, Nutanix, Hyper-V or Linux-bridge KVM they cannot work, and Perch says so rather than rendering empty.

**LLDP needs one thing more: the `lldpd` package.** See [LLDP prerequisite](#lldp-prerequisite) below.

> **All six share ONE budget.** The per-host timeout and the total wall-clock budget are totals across every telemetry phase in a run, not an allowance each — see [Timeouts](#timeouts).

### Enabling

**Administration → Integrations → Plugins → Perch → Edit.**

1. Turn on **Enable host telemetry**. This is the master gate, off by default, because these are the only collectors that leave the appliance and they add network latency to every run.
2. Select the individual layers you want.
3. Optionally turn on **Also run host telemetry on the Instance/Server/Cluster tabs** — see the warning below.

### Privileges

Perch reaches hosts through the Morpheus agent and executes as the agent's user, not as root. On a default agent install that account already holds an unrestricted `NOPASSWD` sudo grant, and nothing further is needed.

**Where that grant has been narrowed**, add a scoped entry per hypervisor. Confirm the binary paths first:

```bash
command -v virsh ovs-appctl multipath iscsiadm lldpctl
```

Then install with `visudo -f /etc/sudoers.d/perch-readonly`, substituting the paths you just confirmed and the agent's username:

```
Cmnd_Alias PERCH_READ = /usr/bin/virsh domstats --interface, \
                        /usr/bin/ovs-appctl dpctl/dump-flows, \
                        /usr/bin/ovs-appctl dpctl/dump-conntrack, \
                        /usr/sbin/multipath -ll, \
                        /usr/sbin/iscsiadm -m session, \
                        /usr/sbin/lldpctl -f keyvalue
morpheus-node ALL=(root) NOPASSWD: PERCH_READ
```

**Do not wildcard the `virsh` arguments.** Unrestricted `virsh` grants destroy, edit and detach on every domain on that host. Pinning to `domstats --interface` grants exactly one read-only call. The same reasoning applies to each of the others.

Verify, as the agent user:

```bash
sudo -u morpheus-node sudo -n virsh domstats --interface 2>&1 | head -5
sudo -u morpheus-node sudo -n ovs-appctl dpctl/dump-flows 2>&1 | head -3
```

A host that cannot escalate **degrades with a named reason** rather than failing the run — the layer reports which host refused and why, so a permissions gap never looks like an empty result.

<a name="lldp-prerequisite"></a>
### LLDP prerequisite — a package, not a setting

**The LLDP layer needs the `lldpd` package on every hypervisor.** Morpheus does not install it and HPE does not support Perch; installing it is your decision.

`tools/perch-lldp-setup.sh` does the whole job — installs the package, configures it receive-only, starts it, and captures what Perch needs to see. Run it on each hypervisor:

```bash
chmod +x perch-lldp-setup.sh
sudo ./perch-lldp-setup.sh
```

On the reference environment the package came from HPE's own mirror, so no third-party repository was needed — **and the script refuses to install from anywhere else.** That will not be true on every estate; where it is not, adding a repository is a decision to make deliberately rather than a step to work around.

**Receive-only, and how to confirm it.** The script sets `DAEMON_ARGS="-c -r"` in `/etc/default/lldpd`: `-r` makes the host listen without advertising itself, and `-c` also receives CDP, which matters because Cisco access ports frequently run CDP with LLDP switched off.

Do not trust the runtime directive — `configure lldp status rx-only` reports success and silently does nothing. The only confirmation is the counters:

```bash
lldpcli show statistics     # transmitted must stay 0 across a 60-second window
```

**A configuration field reports what it was asked. A counter reports what happened.**

**Sudo is mandatory and there is no alternative.** lldpd's control socket is `/run/lldpd.socket` and is root-only; no group membership substitutes for it. If a host with lldpd installed returns nothing, that is the first thing to check — the hypervisor diagnostic's §7b captures the privileged and unprivileged reads separately for exactly this reason.

### A caution about tabs

The tab telemetry switch is deliberately separate from the master switch, because a report is run on purpose and a tab renders on every page view.

With telemetry on, a four-host cluster tab makes a round trip per host per enabled layer. With three layers on, that is twelve round trips and three independent time budgets, and the page can take a couple of minutes to render.

Leave it off unless you want live host data on tab pages and can accept the wait. When it is off, the tab **states plainly** that telemetry is disabled, so an absent flow layer is never mistaken for an empty one.

<a name="timeouts"></a>
### Timeouts

Two settings bound the cost:

- **Per-host command timeout** (default 10s) — how long to wait for one host to answer one command.
- **Total wall-clock budget** (default 45s) — across all hosts **and all six telemetry phases in the run**, not per phase. On exhaustion the collector stops dispatching and degrades, naming the hosts it never reached. With everything enabled on a multi-host estate, the later phases can be starved by the earlier ones; raise the budget or enable fewer layers per run.

A report that hangs is worse than a report missing a layer, which is why both default to finishing.

---

## Upgrading

Upload the new jar the same way. Morpheus replaces the running plugin.

After upgrading, **check the console build lines from step 3.** Asset caching is the most common reason a new version appears to change nothing.

## Uninstalling

Administration → Integrations → Plugins → Perch → Delete.

Perch stores no data of its own — no tables, no files on the appliance, no state on any host. Removing the plugin removes everything it was.
