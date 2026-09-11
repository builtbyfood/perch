# Limitations

Read this before deploying Perch. Most of what follows is a property of what Morpheus stores, or of how Perch reads it — not something a future release quietly fixes.

Perch reports these in the interface as well as here.

---

## 0. Perch has been developed and verified against exactly ONE environment

One Morpheus 9.0 appliance, one private cloud, four KVM hypervisors on Open vSwitch, a dozen or so servers and a handful of networks. **Everything Perch "knows" was learned there.**

**Every number in this documentation is a fact about that one estate, not a universal.** The thresholds, the default layer selections, the type-code mappings that pick icons, the fanout guards, the timeout budgets — each was chosen against one topology and each may be wrong for yours.

That is not modesty for its own sake. It is the single most useful thing to know when a layer renders empty or a glyph looks wrong, because it tells you which question to ask first: *is this a fault, or is my estate simply not the one this was tuned against?* Usually it is the second, and [Diagnostics](DIAGNOSTICS.md) exists to tell the two apart.

Where a limitation below cites a number, read it as an observation rather than a specification.

---

## 1. No tenant filtering

**This is the important one.**

Perch reads the Morpheus database directly, through a connection that performs **no tenant evaluation**. It does not go through the Morpheus API, so it does not inherit Morpheus RBAC.

The consequence: **any user who can open a Perch surface sees the whole estate that surface returns**, regardless of which tenant they belong to or what they can see elsewhere in Morpheus.

The only control is `getMasterOnly()` — restricting the plugin to the master tenant.

**If you run sub-tenants, decide this deliberately before exposing Perch to them.** Role permissions on Reports and Infrastructure limit *who can open a surface*; they do not limit *what the surface contains*.

## 2. What that means concretely

Following from §0, three consequences worth expecting:

- **Type codes may differ.** Cloud, server, network and router types drive icons and host-versus-VM classification. A type Perch has not seen falls back to a generic glyph and a plain label rather than failing — but the glyph may not be the one you would have picked, and the classification may not be the one you expect.
- **Scale is untested.** Layout defaults and fanout guards were tuned for tens of nodes, not hundreds. A large estate may need different thresholds, and not all of them are adjustable.
- **Non-KVM stacks are unverified.** The database-derived layers should work anywhere Morpheus does; host telemetry cannot (see §3). VMware specifically is now *handled* but still unobserved — see §14, which is the most important thing on this page if you run ESXi.

## 3. Host telemetry requires libvirt and Open vSwitch

The host-telemetry layers run `virsh`, `ovs-appctl`, `multipath`, `iscsiadm`, `lldpctl` and `ip` on the hypervisor.

On **VMware, Nutanix, Hyper-V, or KVM using Linux bridges instead of OVS**, these layers cannot work as built. Perch detects this and says so; it does not render an empty graph and leave you guessing.

**LLDP needs more than that.** It requires the `lldpd` package, which Morpheus does not install on any stack — see the README's LLDP section and `tools/perch-lldp-setup.sh`. A host without it reports the package as missing rather than reporting no neighbours, because those are opposite instructions.

That is a limitation to be aware of, not a bug to report — though if you would find those layers valuable on another stack, that is worth an issue.

## 4. Read-only, always

Perch never writes to Morpheus, never provisions, and never changes a host. Host telemetry runs read-only commands.

Stated here as a limitation because it genuinely is one: **Perch will show you a problem and cannot fix it.** There are no remediation actions, and none are planned.

## 5. One address per server

Morpheus stores a single IP address per server. A host's secondary interfaces — storage NICs especially — are not in the database at all.

Perch infers them from the host's own connection tables where host telemetry is enabled, and **marks them as inferred**. Without host telemetry, a host with four NICs is a host with one address.

## 6. Router interfaces carry no address

So a gateway resolves as an external endpoint, named by its address where one can be learned and drawn as an address otherwise.

An address Perch cannot name is drawn as an address rather than dropped — an unnamed node is information; a missing node is not.

## 7. Guest traffic is not connection-tracked

**Tracked Connections** shows host and infrastructure traffic — the cluster control plane, storage paths, management access. Guest traffic appears in **Active Host Flows** instead.

If you are looking for VM-to-VM conversations, that is the layer to enable.

## 8. An empty flow layer is usually correct

The commonest question about **Active Host Flows** is why it is empty. Usually because no VM on that host talks directly to another VM on the same host — which is a fact about your traffic, not a fault.

Enable the external-flow option to see guest-to-gateway traffic instead.

## 9. External systems need credentials

Contrail, Apstra and historical flow feeds are configurable but unauthenticated until credentials are supplied from **Administration → Trust**. Blank is a valid state: the layer reports as not configured rather than broken.

## 10. Settings are global and need a reload

Plugin settings apply to every user and every surface. Changing one requires a page reload before it takes effect.

The tab layer toggles in particular are global — there is no per-user or per-page override.

---

## 11. Host telemetry cannot reach hosts from a Network tab

Not a bug, and not something to retry: it is a consequence of what Morpheus records.

A Network tab is scoped by asking which servers have an interface **attached to that network**. Morpheus records a network attachment for VM interfaces; **hypervisor interfaces generally carry none**. So a network-scoped surface resolves to a set of guests, no hypervisor is ever in scope, and every host-telemetry layer has nowhere to dispatch to.

All six telemetry phases are therefore **structurally empty on every Network tab**, permanently. Perch says so explicitly rather than rendering an empty layer — the banner names the cause and points you at the report or a Cluster/Server tab, which reach hosts normally.

**One caveat, and it is itself unverified.** The mechanism above is a fact about KVM, where no hypervisor carries a `network_id`. On VMware, `esxiUnmanaged` VMs *do* carry one — so this section's reasoning is **not** what empties a VMware Network tab. From 0.3.87 the platform verdict in §14 is evaluated first and answers instead. That ordering is deliberate: the platform fact is true on *every* surface including the report, while the scope fact is true only on this one, so pointing a VMware reviewer at "the report or a Cluster/Server tab" would send them somewhere that also cannot work. Like everything in §14, this has not been observed against a live estate.

## 12. Six telemetry phases share ONE budget

The per-host timeout (10s) and the total wall-clock budget (45s) are **totals across every telemetry phase in a run**, not an allowance each.

With all six enabled on a multi-host estate the later phases can be starved by the earlier ones. When that happens Perch degrades and **names the hosts it never reached**, so a short layer is distinguishable from an empty one — but the arithmetic is worth knowing before enabling everything at once. Raise the budget, or enable fewer layers per run.

## 13. Morpheus does not record all passthrough

Morpheus tracks PCI passthrough well. **USB passthrough it may not record at all** — a device can be genuinely passed through to a guest by the hypervisor while the database still shows it attached to the host with no assignment.

Perch reads the database, so by default it shows what the database says. The optional passthrough extension reads the hypervisor directly and draws the difference as a **finding**, in its own edge style, never merged with the database-derived assignments.

The extension is off by default and gated twice, so the devices layer remains entirely database-derived unless you ask for otherwise.

## 14. VMware / ESXi is handled as designed, and unverified against a real estate

*Applies from **0.3.87**. On **0.3.86** — the build in [Releases](../../../releases) as this is written — none of the behaviour below exists: an ESXi cloud burns the host-telemetry budget attempting SSH to machines that cannot answer, and then advises you to raise that budget. That advice is wrong in the harmful direction, and following it makes the report slower and changes nothing.*

**The status, plainly: handled as designed, unverified against a real VMware estate.**

`esxiHypervisor` contains the substring `hypervisor`, so Perch's hypervisor resolution matched ESXi hosts and dispatched to them. 0.3.87 changes what happens when host telemetry meets a cloud whose hosts are not SSH-reachable Linux hypervisors:

- **No dispatch is attempted, and no budget is spent.** A denylist of `compute_zone_type.code` — seeded with `esxi` and nothing else — marks the cloud non-dispatchable before any host is contacted. Unknown cloud types are deliberately *not* vetoed; they fall through to the previous behaviour, because a wrong denylist entry costs timeouts and says so loudly, while a wrong allowlist entry silently vetoes a site that would have worked.
- **Mixed estates partition rather than veto.** Four KVM hosts and one ESXi host in one report: the KVM hosts are contacted and reported exactly as before, and the ESXi host is excluded ahead of dispatch. A non-dispatchable cloud in your estate does not cost you the telemetry from the rest of it.
- **The exclusion is stated once for the run**, not once per phase, and as a neutral note rather than a failure — six phases each announcing the same fact is five redundant lines on screen.
- **The starvation advice no longer misdirects.** Where the budget ran out and *no* host answered at any point in the run, Perch now says raising the budget will not help. The previous text told you to raise a budget that buys nothing but more waiting.

### Why this section exists

**All of that is unit-tested. None of it has ever been run against a live ESXi cloud.**

An ESXi cloud was stood up for exactly this verification. It hit an unrelated Morpheus permissions problem, and the work was parked before a single Perch run was ever observed against it. The fixtures the behaviour was designed from are real rows, read from that appliance after the cloud synced. The behaviour built on top of them is not.

So the honest claim is the one in the heading — **handled as designed, unverified against a real VMware estate** — and not that VMware works. The tests establish that the code does what the specification says. They establish nothing about whether the specification was right about your estate, and §0 of this document is the standing reason to doubt that.

**If you are pointing Perch at VMware-managed Morpheus, you are the first to do it.** Whatever you see is the most valuable report this beta can receive — including it simply working. Use [`it-worked.yml`](../../../issues/new?template=it-worked.yml) if it drew something, or [`schema-difference.yml`](../../../issues/new?template=schema-difference.yml) if your cloud type code is not `esxi`, since the denylist above is keyed on exactly that string. See [Feedback](../FEEDBACK.md).

---

## Reporting something not on this list

Especially valuable: **anything that looked wrong but did not error.** A wrong count, an odd glyph, a node in the wrong inventory table.

Silent wrongness is the hardest class to catch from logs and the most useful to receive. See [Diagnostics](DIAGNOSTICS.md).
