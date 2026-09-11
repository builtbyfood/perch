# Troubleshooting

Symptom → likely cause → which diagnostic answers it.

Run the [appliance diagnostic](DIAGNOSTICS.md#1-appliance--run-this-first) before filing anything; it answers most of the table below directly.

---

## Quick table

| Symptom | Most likely cause | Where to check |
|---|---|---|
| A layer renders empty | No data of that kind exists | Appliance §10i — zero rows means correct |
| A layer says `degraded` | Schema mismatch; the banner names the failing column | Appliance §6 |
| A layer produced nothing at all | Not selected, or a plugin setting vetoed it | Appliance §5 — the reason names which gate |
| A tile is blank rather than `0` | A stat was never published — a bug, please report | Appliance §4 |
| Graph area blank, tables fine | Assets did not load | Browser console: 404s under `/assets/plugin/perch/` |
| Nodes off-centre, or dead space around the graph | The graph was framed before its container had a size | Browser: `[perch] canvas at construction` |
| A change to the plugin appears to do nothing | Cached assets | Browser: the `[perch-asset] … build <version>` lines |
| Host telemetry layers empty | Not KVM + OVS, or no same-host VM-to-VM traffic | Hypervisor script |
| LLDP layer empty | `lldpd` not installed, or reading it without sudo | Hypervisor script §7b |
| LLDP layer greyed out / not selectable | Two switches gate it, both off by default | Configuration → Host telemetry |
| Host telemetry empty **on a Network tab only** | Structural — no hypervisor is ever in a network's scope | [Limitations §11](../LIMITATIONS.md) |
| Degraded banners appeared after an upgrade | They were always there; four tab surfaces never rendered them | Appliance §6 |
| Compliance empty | No SCAP results stored | Appliance §10i, then the guest checks |
| Report never finishes | Rarely Perch — check the Morpheus job queue | Appliance §9, and `SHOW FULL PROCESSLIST` |
| Wrong icon for a device | Your type codes differ from the ones mapped | Appliance §10f–§10h — send the type list |

---

## The plugin does not appear after upload

Check Administration → Integrations → Plugins for **Perch**, enabled.

- **Not listed** — the upload was rejected. The commonest reason is an appliance older than 9.0.1, which Perch declares as its minimum.
- **Listed but disabled** — enable it.
- **Listed with an older version than the file you uploaded** — the page is cached. Hard-refresh.

## The Topology tab does not appear

Tabs need `Provisioning: Instances` and `Infrastructure: Hosts` permissions; the report needs `Operations: Reports`. Confirm your role has them.

If the report works and the tabs do not, that is a permissions difference, not a plugin fault.

## A change to the plugin appears to do nothing

**Check the build number in the browser console first.**

```
[perch-asset] perch.js build 0.3.102 loaded and executed to completion
```

Morpheus caches plugin assets and the browser caches them again, so a page can run an old build while reporting, truthfully, that it loaded. If the version shown is not the jar you uploaded, hard-refresh; if it persists, the appliance is still serving the previous asset.

**A stale asset and a fix that did not work look identical from every other angle.** This is the one check that separates them.

## The graph area is blank but the tables below it are fine

The graph is drawn by assets served from `/assets/plugin/perch/`. If they 404, nothing renders.

Open the browser console and look for failed requests under that path, and for missing `[perch-asset]` lines — an absent line means that file never finished executing.

## The graph is off-centre, or there is dead space around it

Perch frames the graph once its container has a real size. On a tab, Morpheus renders content before revealing it, so the container measures zero at first and Perch waits.

Console lines that tell the story:

```
[perch] canvas at construction: 0x0 — ZERO, hidden at init; installing visibility watcher
[perch-view] deferred frame armed: watching N element(s) …
[perch-view] deferred frame taken via observer after 4181ms — container is 890x519
```

The last line means it framed correctly. `deferred frame NOT taken: 30s elapsed` means the container never reported a size — worth an issue, with those lines attached.

You can always re-frame manually with the centre control on the graph.

## "Graph too spread to frame — showing focus"

Not an error. One node is far enough from the rest that framing everything would shrink the interesting part to a speck, so Perch frames the focus and tells you, with a **Show everything** button to override.

If it fires when it should not, raise **Clamp the fit below this zoom scale** in plugin settings, or set it to 0 to disable clamping.

## A layer is empty

Check the appliance diagnostic's per-layer row counts first. **Zero rows behind an empty layer means the layer is correct.**

If rows exist and the layer is still empty, that is a bug — include the section-5 and section-10i output.

## A layer says "degraded"

Perch expected a table or column your Morpheus does not have. The banner names it, and the appliance diagnostic's schema-drift section lists every such mismatch.

This is the most useful thing you can send from a different Morpheus version — it is precisely the difference between your schema and the one Perch was built against.

## Host telemetry layers are empty

Work through these in order:

1. **Is the master switch on?** Plugin settings → Enable host telemetry. Off by default. LLDP needs a second switch of its own — see below.
2. **On a tab?** Tab telemetry is a *separate* switch, also off by default. The tab states when it is off.
   **On a Network tab it will always be empty**, no matter what is switched on — no hypervisor is ever in a network's scope. See [Limitations §11](../LIMITATIONS.md); use the report or a Cluster/Server tab.
3. **Is the host KVM + Open vSwitch?** These layers cannot work otherwise. The hypervisor script detects this.
4. **Can the agent escalate?** A host that cannot degrades with a named reason rather than failing — check whether the layer reports a specific host.
5. **Is there any traffic to see?** An empty flow layer usually means no VM on that host talks to another VM on the same host.

## The LLDP layer is empty, or will not switch on

**Not selectable at all?** Two switches gate it, both off by default: **Enable host telemetry** and **Enable LLDP neighbour discovery**. They are deliberately separate — every other telemetry layer runs commands already on an MVM hypervisor, while LLDP needs a package installed, and that should be its own decision rather than a side effect of enabling traffic volume.

**On, but empty?** Three captures, in this order:

```bash
# 1. Is the package even there?
command -v lldpctl || echo "lldpd not installed"

# 2. Privileged read — this is the one Perch makes
sudo lldpctl -f keyvalue | head -20

# 3. Unprivileged read, for contrast
lldpctl -f keyvalue | head -20
```

If 2 returns neighbours and 3 returns nothing, that is the expected shape: lldpd's control socket is root-only and no group membership substitutes for it. If **both** are empty and the package is installed, the host is genuinely hearing nothing — check that the switch port has LLDP or CDP enabled, and that lldpd was started with `-c` so CDP is received too.

The hypervisor diagnostic's §7b captures all three, which is why it is the right thing to attach.

**Neighbours appear, but the port label reads as an interface index rather than a name** — the neighbour is advertising a port ID Perch cannot resolve to a name. That is a fact about the switch's advertisement, not a fault; send the §7b capture if the label looks wrong.

## I upgraded and now I see "degraded" banners everywhere

**The upgrade did not create them. It made them visible.**

Before 0.3.77 only the report surface rendered collector banners; the four tab surfaces carried the same information in their payload and simply never drew it. A layer that had been quietly degrading for weeks looked healthy on a tab and always had.

So a banner appearing after an upgrade means one of two things, and they are not the same:

- **A pre-existing condition, newly shown.** Overwhelmingly the common case. Read the banner — it names the failing table or column — and check the appliance diagnostic's schema-drift section against it.
- **Something the new version actually broke.** Distinguishable because the banner names something the previous version was not reading at all.

Either way the banner names the cause, and the appliance diagnostic's §6 is the section to send.

## The report is slow, or times out

Host telemetry adds a round trip per host per enabled layer. Two settings bound it — the per-host command timeout (default 10s) and the total wall-clock budget (default 45s). On exhaustion the collector degrades and names the hosts it never reached, rather than hanging.

If the report is slow with telemetry **off**, it is likely the Morpheus job queue rather than Perch. Check `SHOW FULL PROCESSLIST` on the appliance database.

## A tab takes minutes to render

Almost certainly tab telemetry. A four-host cluster with three telemetry layers makes twelve round trips — and all the enabled phases share **one** budget between them, so with several on, the later ones can be starved by the earlier ones.

Turn off **Also run host telemetry on the tabs** and use the report for live host data.

## Icons are wrong for my hardware

Perch maps cloud, server, network and router type codes to glyphs. Codes it has not seen fall back to a generic glyph and a plain label rather than failing.

The appliance diagnostic lists your actual type codes. **Send that list** — it is exactly what is needed to add the mapping.

## Compliance is empty

Perch reads stored SCAP results; it never runs scans. Empty means no results are stored.

On Ubuntu 24.04 there is a known Morpheus issue: the SCAP bootstrap installs `libopenscap8`, dropped in that release, and fails quietly so `oscap` never lands.

```bash
sudo apt install -y openscap-scanner unzip
```

## Something looks wrong but nothing errored

**This is the most valuable thing to report** — a wrong count, an odd glyph, a node in the wrong inventory table.

It is also the hardest to find from logs, so please include what you expected alongside what you saw. See [Diagnostics §5](DIAGNOSTICS.md#5-tell-us-what-is-different).
