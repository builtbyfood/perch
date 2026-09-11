# Diagnostics

Perch has been developed and verified against one type of environment, yours is almost certainly different, and that difference is usually the answer.

These tools exist to capture *what is different*, so an empty layer or a wrong glyph can be diagnosed rather than guessed at.

> ### If nothing is broken, this page is still for you
>
> The rest of this document is written for the case where something went wrong. Most of it will not apply to you, and that is the outcome we are hoping for.
>
> **A working run is the most valuable report this beta can receive** — Perch has been verified against exactly one estate, so a second one that renders correctly is the only thing that turns a tuned-for-one number into a verified one. §1 below still applies: run the appliance script, because §10e–10h of its output are your type codes and they are the finding.
>
> Then use [It worked — here are my numbers](../../../issues/new?template=it-worked.yml), and see [Feedback](../FEEDBACK.md) for why that matters as much as a bug report.

---

## The three scripts

Everything Perch collects comes from these three, and this table is the whole of it — what each one gathers, where you run it, where it writes, and what to do with the file afterwards.

| | [`perch-diag-appliance.sh`](../scripts/perch-diag-appliance.sh) | [`perch-diag-hypervisor.sh`](../scripts/perch-diag-hypervisor.sh) | [`perch-diag-queries.sql`](../scripts/perch-diag-queries.sql) |
|---|---|---|---|
| **Run it on** | The Morpheus **appliance** — the machine serving the UI | **Each hypervisor** Morpheus manages | The appliance database |
| **When** | **Always.** This is the important one | Only if you are using host-telemetry layers | Only if the appliance script reported `SKIPPED` for §10 |
| **How** | `sudo ./perch-diag-appliance.sh` | `./perch-diag-hypervisor.sh` | Piped into `mysql` — see §1b |
| **What it collects** | Morpheus version, plugin load state, recent Perch log lines, every collector's status and the gate that refused it, schema-drift warnings, the raw submitted report options, and a full database survey — tables, guarded columns, type codes and per-layer row counts | Exactly the commands Perch runs on a host — `virsh`, `ovs-appctl`, `multipath`, `iscsiadm`, `lldpctl`, `ip` — plus the checks that explain why one of them might not work, including the privileged and unprivileged LLDP reads captured separately | The database half of the appliance script, run by hand: the same table, column, type-code and row-count survey |
| **Writes to** | `/tmp/perch-diag-appliance-<host>-<date>.txt` | `/tmp/perch-diag-host-<host>-<date>.txt` | Wherever you redirect it — conventionally `/tmp/perch-diag-db.txt` |
| **Then what** | **Read it, redact it, attach it to the issue.** Required by every issue form | Read, redact, attach — **one file per hypervisor** | Read, redact, attach alongside the appliance file |
| **Safety** | Read-only. Selects no credential-bearing column | Read-only. Starts, stops and edits nothing | Read-only. Selects no credential column |

**Everything except host telemetry is database-only.** If your layers are empty and you are not using host telemetry, you never need to touch a hypervisor — the appliance script has the answer.

**All three describe your estate**, and the issue tracker is public. [FEEDBACK.md](../FEEDBACK.md#redacting-without-destroying-the-value) lists which fields identify you and how to redact them without making the file useless. The five credential-bearing columns — `config`, `ssh_password`, `raw_data`, `last_stats`, `service_password` — are excluded by construction, so there are no secrets to find; the job left to you is identity.

### The fourth file in `scripts/` is not a diagnostic

[`perch-lldp-setup.sh`](../scripts/perch-lldp-setup.sh) **installs and configures `lldpd` receive-only** on a hypervisor. It is setup, it makes changes, and it collects nothing. It is in the same directory as the three above and is listed here only so that nobody runs it looking for a log file. See [Install](../INSTALL.md#lldp-prerequisite).

### Two more diagnostics that are not scripts

| | Where | Needed for |
|---|---|---|
| Browser snippet, §3 | Your browser, on a rendered surface | Any rendering problem — blank graph, off-centre, missing nodes |
| Guest checks, §4 | Inside a guest VM | Only if compliance is involved |

---

## 1. Appliance — run this first

```bash
chmod +x perch-diag-appliance.sh
sudo ./perch-diag-appliance.sh
# writes /tmp/perch-diag-appliance-<host>-<date>.txt
```

Read-only. Collects the Morpheus version, plugin load state, recent Perch log lines, every collector's status and skip reason, schema-drift warnings, the raw submitted report options, and a database survey.

**Run a report first**, so there is something in the log: Operations → Reports → Perch → Run Now, wait for it to finish, then run the script.

### What it answers

| Section | Question |
|---|---|
| 2 | Did the plugin load, and which version is actually running? |
| 5 | Why did a layer not run? *Which* gate refused — run option, plugin setting, or missing table |
| 6 | **Schema drift** — tables and columns Perch expected that your Morpheus does not have. The single most useful section |
| 7 | What the report options form actually submitted |
| 10b/10c | Which tables and guarded columns exist in your schema |
| 10e–10h | Your cloud, server, network and router **types** — these drive icons and host-vs-VM classification |
| 10i | Per-layer row counts. **An empty layer with zero rows behind it is correct, not broken** |

## 1b. The database survey by hand — only if §10 said SKIPPED

The appliance script runs [`perch-diag-queries.sql`](../scripts/perch-diag-queries.sql) for you. Run it yourself only when the script reported `SKIPPED` for section 10 — which happens when Morpheus uses an external database, or when the password could not be read from `/etc/morpheus/morpheus-secrets.json`.

```bash
/opt/morpheus/embedded/mysql/bin/mysql -u morpheus -h 127.0.0.1 -p morpheus \
  --force --table < perch-diag-queries.sql > /tmp/perch-diag-db.txt 2>&1
```

Two flags that are not optional:

- **`-h 127.0.0.1`** — `localhost` makes the client use the unix socket, which is refused.
- **`--force`** — a query against a table your Morpheus does not have must not stop the rest. **Those errors are themselves the finding**, so leave them in the output and send them.

Read-only, and it selects no credential column. Attach `/tmp/perch-diag-db.txt` alongside the appliance file — reviewed and redacted like everything else.

## 2. Hypervisors — only for host telemetry

```bash
chmod +x perch-diag-hypervisor.sh
./perch-diag-hypervisor.sh
# writes /tmp/perch-diag-host-<host>-<date>.txt
```

Run on **each** hypervisor. Read-only — it runs the same commands Perch runs, plus the checks that explain why one of them might not work.

**A likely finding: your stack may not be KVM + Open vSwitch.** Host telemetry assumes libvirt and OVS. On VMware, Nutanix, Hyper-V or Linux-bridge KVM it cannot work as built, and the script says so plainly. That is a limitation to report, not a bug to debug.

The script also answers the commonest flow-layer question — **why is it empty?** Usually because no VM on that host talks directly to another VM on the same host. That is a fact about your traffic.

**§7b is the LLDP section**, and it captures the privileged and unprivileged reads *separately* on purpose. lldpd's control socket is root-only, so "installed but returns nothing" and "installed but read without sudo" produce the same empty output from one command and are told apart only by running both. If the LLDP layer is empty, that section is the answer.

## 3. Browser — for anything visual

Open a surface, then the browser console (F12).

**Check the build first.** Every Perch asset announces which build it is:

```
[perch-asset] perch.js build 0.3.102 loaded and executed to completion
```

If that version is older than the jar you uploaded, you are looking at a cached asset, not at the plugin's behaviour. Hard-refresh before investigating anything else. A missing line means that file never finished executing.

**Graph integrity:**

```javascript
var g = JSON.parse(document.getElementById('perch-graph-data').dataset.graph);
var ids = new Set(g.nodes.map(n => n.id));
var bad = g.edges.filter(e => !ids.has(e.from) || !ids.has(e.to));
console.log('nodes', g.nodes.length, 'edges', g.edges.length, 'dangling', bad.length);

// which glyph each node got
console.log(g.nodes.reduce((a,n) => (a[n.group]=(a[n.group]||0)+1, a), {}));
```

**`dangling` must be 0.** Anything else is a real bug — please include the output.

**Clear the console filter box before you look.** A leftover filter silently hides Perch's own lines.

**For centring and layout problems**, Perch logs what it measured:

```
[perch] canvas at construction: WxH — …
```

`0x0` means the graph was built into a container that had not been rendered yet — normal on a tab, which is why Perch waits for a real size before framing. Include this line and any following `[perch-view]` lines.

## 4. Guest VMs — only for compliance

Perch reads SCAP results; it does not run scans. If the compliance layer is empty, the scan did not happen or did not store results.

```bash
which oscap || echo "oscap not installed — SCAP scans cannot run"
ls /usr/share/xml/scap/ssg/content/ 2>/dev/null | head
sudo systemctl status morpheus-node --no-pager | head -15
```

Known Morpheus issue on Ubuntu 24.04: the SCAP bootstrap installs `libopenscap8`, a package dropped in 24.04. It fails quietly and `oscap` never lands. Workaround:

```bash
sudo apt install -y openscap-scanner unzip
```

---

## 5. Tell us what is different

The scripts capture numbers; these are the questions they cannot answer. A one-line answer to each is worth more than a lot of log output.

**These five are the body of the [It worked — here are my numbers](../../../issues/new?template=it-worked.yml) form**, which prompts for them one at a time. Use the form if Perch drew your estate; answer them here in the issue body if you are reporting a fault. Either way they are the same five questions, and they are the ones that matter most.

1. **Hypervisor / cloud type** — VMware, Nutanix, Hyper-V, KVM, AWS, Azure, GCP, mixed?
2. **Scale** — how many servers, networks, clouds? Layouts and fanout guards are tuned to small numbers.
3. **Multi-tenant?** Perch does not filter by tenant — see [Limitations](../LIMITATIONS.md). If you run sub-tenants, say so.
4. **Which layers are empty**, and did you expect data there? Empty is often correct.
5. **Anything that looked wrong but did not error** — a wrong count, an odd glyph, a node in the wrong table. Silent wrongness is the most valuable bug class and the hardest to catch from logs.

## 6. What to send

- `/tmp/perch-diag-appliance-*.txt` — always
- `/tmp/perch-diag-host-*.txt` — one per hypervisor, if using host telemetry
- The browser console output from §3
- A screenshot showing the problem
- Your answers to §5

Which form to open — and why a working run is worth as much as a fault — is in [Feedback](../FEEDBACK.md).

### Review before sending

**The output describes your estate.** It contains hostnames, IP addresses, cloud, server and network names, MAC addresses and counts.

It deliberately excludes every credential-bearing column — configuration blobs, passwords, raw payloads and cached stats — because those hold encrypted secrets and no diagnostic reads them. But the rest is real infrastructure detail, and a public issue tracker is public. **Review the file, and redact whatever you would not post publicly.**

If a problem can only be explained with sensitive detail, say so in the issue and we will find another route.

**[FEEDBACK.md](../FEEDBACK.md#redacting-without-destroying-the-value) has the detail**: which fields in each file identify you, the five credential-bearing columns no diagnostic reads, and how to substitute names consistently so the file is still diagnosable afterwards. Blanking everything is the common mistake — it costs you the work and leaves us nothing to read.
