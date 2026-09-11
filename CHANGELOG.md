# Changelog

Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

User-visible changes only. Perch is distributed as a binary; this file records
what changed for the person running it.

---

## 0.3.102

### Fixed

- **Kubernetes and Security Groups no longer report "degraded" when nothing is wrong.** Both layers collapsed two different facts into one word: an estate that has none of the thing, and a schema that cannot describe the ones it has. Those need opposite responses, and the banner said the same thing for both.

  - **Kubernetes** now checks whether any cluster exists before anything else. None → the layer is simply empty and says nothing. Clusters present → it reports that this schema records no pod namespace, and asks for a schema-difference issue. The pod query that could never succeed — it selected a column `container` does not have — is deleted rather than rewritten.
  - **Security groups** now check for groups first. None → empty. Groups present but membership unreadable → the groups still render and the layer says what it could not determine.

- **A security-group layer on an instance, server or cluster tab no longer claims your estate has no security groups** when it has them but cannot scope them. Those surfaces select groups by membership, so with membership unreadable every group was pruned and the result read as "none exist".

### Changed

- **New status: `unsupported`**, shown muted rather than amber. It means this Morpheus cannot answer the question at all — established by checking the schema *before* querying, never by a query failing, so it can never be confused with a transient error. `degraded` still means something went wrong and is worth your attention.
- Security-group membership is read from `security_group_association` and attachment from `security_group_location`, both guarded. Reference types Perch does not recognise are **named** in the banner rather than dropped, so an estate using a type it has not met produces a sentence rather than silence.

---

## 0.3.101

### Fixed

- **The report failed to run.** Every attempt ended in an internal error immediately after the plugin settings were read, on every appliance, since 0.3.88 — thirteen releases. The topology tabs were unaffected throughout.

  The cause was one unqualified name. The report builds its database handle inline where every tab names it first, so a line added with the schema cache in 0.3.88 referred to something that did not exist in that method. Groovy resolves such a name at run time rather than rejecting it at compile time, so it built, shipped, and failed only when a report was actually run.

  **If you have been running reports on 0.3.88 through 0.3.100, they have been failing.** Upgrade and re-run; nothing about your data changed, and no earlier report result was corrupted — they simply were not produced.

### Changed

- The report is now covered end to end by the test suite. It had a rendering test and no collection test, so the half that opens the database and runs every layer was never executed by a single test — which is why a broken build passed and shipped.

---

## 0.3.100

### Fixed

- **The excluded-hypervisor note counted dispatches, not hosts.** With every host layer on, Perch runs seven commands per hypervisor — so the note reported "28 host(s) were contacted" about a four-host cluster. It now counts machines, which is what the sentence claims.
- **The note named hosts the page never contained.** The exclusion list is worked out for the whole estate, so a Cluster tab named an ESXi host that is not a member of that cluster — true about your estate, and an answer to a question the page did not ask. It now names only hosts that were in scope for the surface you are looking at.

---

## 0.3.99

### Changed

- **All four Topology tabs now reuse a collected graph** for `perchTabCacheSeconds`. The Cluster tab was the last to move; the caveat in the previous entry no longer applies.

### Measured

Cold means the first view of a page; warm means a second view inside the cache
lifetime. All figures below are from the reference appliance **after** the
0.3.97 change described under *Changed*, so they are comparable with each other.

| Surface | Cold | Warm |
|---|---|---|
| Server tab (1 host) | ~1.1 s | **2 ms** |
| Instance tab | ~1.2 s | — |
| Cluster tab (4 hosts) | ~3.6 s first, ~2.3 s after | — |
| Network tab (0 hosts) | ~0.5 s | 34 ms |

**A correction, recorded rather than quietly replaced.** An earlier draft of this
entry gave the server tab's cold cost as 4.4 s. That measurement was real, and it
was taken on 0.3.94–0.3.96 — before the change that stopped every host layer
re-running the same hypervisor lookup. It was then compared against a cluster
figure taken after that change, so the table set two versions side by side and
read as a difference between surfaces when it was mostly a difference between
builds. **A measurement outlives the code it measured, and stops being true
without becoming false-looking.**

The first cluster view is slower than later ones by more than caching explains;
that gap is JIT warm-up, not collection.

What caching does not fix: **host telemetry dispatches sequentially.** A cold view
of an N-host scope costs roughly N × 7 × 150 ms of SSH, paid once per
`perchTabCacheSeconds`. Parallel dispatch is queued for after this release.

---

## 0.3.98

### Changed

- **Detail pages no longer re-collect the topology on every view.** Morpheus renders every plugin tab when a page *loads*, not when a tab is clicked — so opening one server page ran a full collection for each tab, whether or not anyone looked at it. Collected graphs are now reused for `perchTabCacheSeconds` (default 120, 0 disables). Covers the Instance, Server and Network tabs; the Cluster tab follows in 0.3.99.
- **A layer that cannot run on a surface stops working that out the slow way.** On a Network tab the host-telemetry layers spent about three seconds between them establishing something a check needing no database already knew. The verdict is now the first thing each of them does.
- **The tab footer shows when the data was collected**, never when the page was drawn, so a reused graph is never presented as live.
- The report is unaffected in every case — it is run deliberately, and answering a Run with a two-minute-old graph would answer a different question.

### Fixed

- **The tab cache never actually hit.** A settings *refresh* was treated as a settings *change*, so every cached graph was discarded every 30 seconds and a 120-second cache could never be reached. A refresh that reads back an identical document is no longer an event; one that reads back a changed value names the setting in the log.
- **The render timing line reported the opposite of what happened** on a cold render, attributing collection time to rendering.
- **The disabled-tab notice showed "Perch unknown"** instead of the build number.
- Phase numbers removed from the settings dialog's help text, where several had survived the 0.3.81 sweep.

---

## 0.3.93

### Fixed

- **The excluded-hypervisor note no longer claims contact that did not happen.** It counted how many hosts were *dispatchable* and said they "were contacted normally" — but on a surface that then gated dispatch, nobody was contacted at all. It is now built from what the dispatch actually did, and says **"No host was contacted on this surface"** when that is what occurred.

### Changed

- **A layer that cannot run on a surface is no longer reported as degraded.** It has its own state: one muted line, no amber. `degraded` means Perch tried and something went wrong and you should look; inapplicable means the question does not apply here and there is nothing to look at. Five ambers on a Network tab where nothing is wrong teaches you to stop reading amber.
- **Layers inapplicable for the same reason share one banner line**, naming all of them, with the reason stated once — instead of five copies of one sentence crowding out everything else.
- **The peers banner references the collector's banner rather than quoting it.** The same sentence used to appear in two places, which drift apart as soon as either is edited and leave the reader unable to tell one fact from two.

---

## 0.3.92

### Changed

- No user-visible change. Records, in the developer notes and in two tests, that a tab's visibility check performs one settings read per cache lifetime on the request thread — the mechanism that lets `hidden` be undone from the settings screen rather than being a one-way door.

---

## 0.3.91

### Changed

- **The tab off-switch is now visible rather than invisible.** `Show the Topology tab on detail pages` (a checkbox) is replaced by **`Topology tab on detail pages`** with three states:
  - **`on`** *(default)* — collect and draw, as before.
  - **`off`** — **the tab still appears** and states that it is switched off, naming the setting and where to change it. Perch collects nothing: no database connection, no collectors, no graph, no assets loaded.
  - **`hidden`** — no tab at all. This was the old checkbox's only off position.

  The reason for the middle state: a missing tab is indistinguishable from an uninstalled plugin, so anyone turning Perch off to test whether it was slowing their detail pages had no confirmation that they had. An absent thing cannot explain itself.

  **To confirm it stopped collecting**, the render still logs a line — `mode=off collectors=0`. A page that merely looks quicker is not evidence.

- **The report is unaffected in every mode**, and the notice says so. A report is run deliberately; a tab renders on every page view.

### Added

- **`Settings cache lifetime (seconds)`**, default 30. Morpheus gives plugins no notification when settings are saved — there is no callback in the plugin API — so Perch re-reads on a timer. **A change to the tab mode takes effect within this many seconds**, which is documented rather than left to look like an inconsistency.

---

## 0.3.90

### Changed

- **The documentation is now published only here.** It previously existed in two places at two versions, which is how this repository sat thirteen releases behind while the private copy stayed current. Two documents that disagree do so silently; one cannot drift from itself.
- **`tools/` is now `scripts/`.** The directory holds setup as well as diagnosis, and the old name undersold what `perch-lldp-setup.sh` does.
- `INSTALL.md` and `LIMITATIONS.md` moved to the repository root, alongside the README, `SECURITY.md` and this file.

### Added

- **[SECURITY.md](SECURITY.md)** — the tenancy and RBAC statement in full, the columns Perch never reads, what the diagnostic output contains, and a **private** route for vulnerability reports. Security problems go to GitHub's private advisory form, never to a public issue: an issue is visible the moment it is filed and cannot be made private afterwards.
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how Perch works and what each layer costs: collectors, overlays, the four banner statuses, the five surfaces, and why tab renders are cheaper than they were.
- **[docs/SCHEMA.md](docs/SCHEMA.md)** — every table Perch reads and the four discriminators that decide how things are drawn, so a schema-difference issue can name the mismatch precisely.
- Screenshot placeholders, so no image reference renders broken while captures are outstanding.

---

## 0.3.89

### Changed

- No user-visible change. A standing check now scans everything that ships — templates, browser assets, the plugin's string literals and this repository — for identifiers belonging to the environment Perch was developed against. It was already clean; this is what keeps it clean as documents are added.

---

## 0.3.88

### Changed

- **Detail pages no longer do Perch work before showing the tab.** The Instance tab made a blocking API call on every instance page view to decide whether to appear at all. It no longer does, and neither does any other tab.
- **The appliance schema is read once and reused** for ten minutes rather than on every render, configurable and droppable to 0. A failed read is never cached — a transient database problem must not pin every schema check to its fallback for ten minutes.

### Added

- **`Show the Topology tab on detail pages`** — a plugin setting, on by default. Turn it off to remove the Topology tab from every detail page without uninstalling Perch and without affecting the report. **This is the first thing to flip if detail pages become slow.**
- **`Schema cache lifetime (minutes)`** — default 10.
- **One log line per render**, naming the surface and splitting the time into schema, collect and render, with per-collector milliseconds alongside. If Perch is slow, this is what says so with numbers — and if it is not, this is what shows that too.

---

## 0.3.86

### Read this first if you are upgrading

**Collector status banners now render on the Instance, Server, Cluster and Network tabs.** You may see layers reported as `degraded` or `failed` immediately after upgrading, on surfaces that looked fine before.

**Those states are not new and the upgrade did not cause them.** Every one of them was being computed, and logged, from the day the tabs shipped — the tab templates simply had no markup to display it, so the reasons were written into the page model and dropped. The report has always shown them; four surfaces never did.

So an upgrade that surfaces a `degraded` layer has told you something that was already true. The reason text names the cause: a schema column your Morpheus does not have, a host that could not be reached, a phase that never dispatched.

**A related fix in the same release:** the activity overlay ran a query that failed on every render, on every surface, since the guard around it was added. Nothing reported it, because that layer's own failure could not reach a page either. If you noticed empty activity tiles or nodes that were never badged with recent activity, that is why — and it now works.

### Added

- **LLDP neighbours** — a new layer showing switches and neighbours seen on the wire, including hypervisor ports that carry no network attachment and are therefore invisible to every other layer. Requires the `lldpd` package on each hypervisor; `scripts/perch-lldp-setup.sh` installs and configures it. Off by default, behind its own switch.
- **Observed passthrough** — an optional extension to the hardware-devices layer that reads the hypervisor directly and draws passthrough Morpheus has not recorded, in a distinct edge style, as a finding rather than a correction. Off by default and gated twice, so the devices layer stays entirely database-derived unless you ask otherwise.
- **Search exclusion** — prefix any term with `-` to exclude it: `-group:vm`, `group:vm -compliance:pass`, `-web01`.
- **`lldp:` and `switchport:` filters**, so you can select neighbours by advertised capability or find every link on a labelled switch port.
- **The full search on every surface.** The tabs previously ran a reduced version with no modes, no hop control and no match count.
- **Edge label control**, defaulting off on graphs carrying enough labelled edges to overlap and on below that. Hover a node to reveal its own edge labels; an active search keeps labels on its matches.

### Changed

- The search counter reads **`3 matches, 11 shown`**. It previously reported matches only — which never changes when you change the hop count, so the one number on screen sat still while the graph grew. The mechanism was correct; the feedback was not.
- **Phase numbers removed from every label an operator reads.** The sequence is internal, non-contiguous and non-chronological; `Tracked Connections (21)` invited a question about where 1–20 went and answered nothing.
- Layer, legend and banner text no longer carry them either.
- The Network tab's first tile reads **Attached servers**, not *Member hosts*. It counts every server with an interface on the network, most of which are not hypervisors — so beside a `Hosts: 0` tile the old wording read as a contradiction.
- The plugin jar now carries its own `META-INF/LICENSE` and `META-INF/NOTICE`, so it stays compliant when it travels away from this repository.
- Every browser asset announces **which build it is**, so a cached asset can be told apart from a change that did not take effect.

### Fixed

- **Search and the layer controls no longer fight over visibility.** Typing a query could un-hide nodes the layer or endpoint-class controls had hidden, and toggling a layer afterwards could wipe the search. Filtering is now decided in one place, from every control at once.
- **The activity overlay's container query**, failing on every render since the guard around it was added (see above).
- **Edge labels on edges added after the graph first drew** are no longer blanked.
- Host telemetry on a **Network tab** now says why it collected nothing, instead of rendering an empty layer indistinguishable from "no data exists" — see [Limitations](LIMITATIONS.md).

### Known limitations worth re-reading

[docs/LIMITATIONS.md](LIMITATIONS.md) is current as of this release, and two entries are new: host telemetry **cannot reach hosts from a Network tab** at all, and **six telemetry phases now share one 45-second budget**.

---

## 0.3.74 — Initial public release

First public release. Perch draws your Morpheus estate as an interactive
topology graph, on five surfaces, from data Morpheus already holds.

### Surfaces

- **Estate report** — every cloud, host, VM, network and router in one graph,
  with an inventory table beneath it.
- **Topology tabs** on instance, server, cluster and network detail pages, each
  scoped to what that object touches.
- **Scope control** on the scoped surfaces: focus only, peers with observed
  traffic, or everything sharing a network.

### Layers

- Core compute and networking, routers, security groups and Kubernetes, from
  the Morpheus database.
- **Datastores** and the volumes that attach servers to them.
- **Hardware devices**, with assigned devices edged to the guest that holds
  them — GPU passthrough is visible as a graph edge.
- **Overlays** decorating existing nodes rather than adding new ones:
  compliance tier, backup coverage, monitoring health and recent activity.
- **Host telemetry**, off by default, read directly from the hypervisors over
  the Morpheus agent: per-guest traffic volume, live datapath flows, tracked
  connections, and multipath / iSCSI storage paths.
- **External overlays** for Contrail, Apstra and historical flow replay, with a
  time slider.

### Interface

- Every layer independently toggleable, labelled with where its data comes from
  and what it costs.
- Search and filter by predicate — `compliance:critical`, `backup:unprotected`,
  `health:pending`, `group:vm_windows` — or by plain text.
- Node detail on hover: compliance, backup freshness, monitoring health,
  activity, traffic volume and storage attachments.
- **Resizable graph** — drag the bottom edge, or expand to fill the window. The
  height is remembered per surface.
- Dark and light themes, following the Morpheus theme.

### Behaviour worth knowing about

- **A layer that finds nothing says why.** An empty layer, a failed query and a
  layer that was never selected are three different states and Perch reports
  them as three different states.
- **A layer whose schema does not match degrades with a named reason** rather
  than rendering as empty.
- **A host that cannot be reached is named.** Host telemetry that fails on one
  hypervisor reports which one, rather than silently dropping it.
- **Time budgets are bounded.** Host telemetry has a per-host timeout and a
  total wall-clock budget; on exhaustion it degrades and names the hosts it
  never reached. A report that hangs is worse than one missing a layer.
- **An address Perch cannot name is drawn as an address**, not dropped.
- **Where the full graph would be unreadable**, Perch frames the focus instead
  and says so, with a control to show everything.

### Packaging

- The jar carries its own `META-INF/LICENSE` and `META-INF/NOTICE`, so it stays
  compliant when it travels detached from this repository.
- Every browser asset announces which build it is, so a cached asset can be
  told apart from a change that did not take effect.

### Known limitations

Read [docs/LIMITATIONS.md](LIMITATIONS.md) before deploying. In short:
**Perch does not filter by tenant**, it is read-only, host telemetry requires
libvirt and Open vSwitch, and it has been verified against a single small
KVM / Open vSwitch environment.
