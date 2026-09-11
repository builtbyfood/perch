# How Perch works

Enough of the internals to reason about cost, trust it with your database, and
know which question to ask when something looks wrong. This is the user-level
account; it is not a contributor guide.

---

## The shape of it

Perch is a **read-only reporting plugin**. It runs inside Morpheus, reads the
Morpheus database, optionally runs read-only commands on your hypervisors, and
draws a graph. It stores nothing of its own.

```
   Morpheus database ──┐
                       ├──▶  collectors  ──▶  one merged graph  ──▶  five surfaces
   hypervisors (SSH) ──┤        (layers)
   external REST ──────┘
```

**Perch does not sync anything.** It has no inventory of its own and no cache of
your estate: it reads what Morpheus already collected, at the moment you ask.
That is why a Perch graph can never be more current than Morpheus's own sync, and
why it can never be stale in a way Morpheus is not.

---

## Collectors, and why layers cost different amounts

Each layer is a **collector**: something that runs, contributes nodes and edges,
and reports its own status. The surface merges them into one graph.

Collectors fall into three cost classes, and the class is the whole reason for
the defaults:

| Class | What it does | Default |
|---|---|---|
| **Local SQL** | One query against the appliance database | **on** |
| **SSH** | A read-only command on each hypervisor, via the Morpheus agent | off |
| **External REST** | An HTTP call to a system outside Morpheus | off |

**Everything that leaves the Morpheus database is off by default.** That is the
whole rule, and it is why enabling a layer is a decision rather than a
preference.

A collector that fails is caught, and its failure is reported in the banner. **One
broken layer never blanks the graph.**

---

## Overlays are different from layers

An **overlay** decorates nodes another collector already emitted, rather than
adding nodes of its own — the compliance border, the backup glow, the monitoring
icon, the activity badge.

One property matters to you: **an overlay that did not run cleanly decorates
nothing.** It does not partially decorate, and it does not silently leave nodes
unmarked as though they had been checked and passed. Empty findings are not a
known negative.

So an unlit compliance overlay means "no compliance data", never "everything
passed".

---

## Status, and the four things a banner can say

Every collector publishes a status, and the banner shows the ones worth your
attention:

| Status | Means | Shown |
|---|---|---|
| `failed` | The collector threw. Its layer is absent. | red |
| `degraded` | It ran but could not complete — a missing column, an unreachable host, a phase that never dispatched. **The reason names the cause.** | red |
| `note` | Something worth knowing about a run that otherwise succeeded. | neutral |
| `ok` / `empty` | Nothing to say. | hidden |

**`empty` and `degraded` are deliberately different, everywhere.** A layer with
no data and a layer that could not read is the distinction Perch spends the most
effort preserving, because they look identical on screen and lead to opposite
actions. Wherever Perch can tell them apart, the banner says which one it is.

`note` rides alongside a healthy status and can never change one. If a run
excluded some hosts but read the rest correctly, you get the real result plus a
note saying what was excluded — not a degraded layer.

---

## The five surfaces, and why the tabs are cheaper

| Surface | Scope |
|---|---|
| **Report** | The whole estate, or one cloud |
| **Instance tab** | That instance and its blast radius |
| **Server tab** | That server, its guests or its host |
| **Cluster tab** | The cluster's member hosts |
| **Network tab** | Servers attached to that network |

A scoped surface resolves its focus **before** any collector runs, and every
collector honours that scope. A per-instance view never queries the whole fleet
and never fans SSH across it.

**Tabs render on every page view; the report is run deliberately.** That
asymmetry drives two things: host telemetry has a separate switch for tabs, off
by default, and the tab's own visibility check does no database work at all. If
detail pages ever feel slow, the `Show the Topology tab on detail pages` setting
turns every tab off without uninstalling anything.

---

## Access control — read this

**Perch reads the database directly, through a connection that does no tenant
evaluation.** It does not go through the Morpheus API and does not inherit
Morpheus RBAC.

Any user who can open a Perch surface sees the whole estate that surface returns.
Role permissions control *who can open a surface*; they do not control *what the
surface contains*. `getMasterOnly()` is the only control.

This is a property of how Perch reads, not a defect awaiting a patch. It is
stated in full in [SECURITY.md](../SECURITY.md), and if you run sub-tenants you
should read that before exposing Perch to them.

**Perch has no functioning plugin-owned routes.** Its code declares four, and on
the verified appliance none of them ever answered. Nothing in Perch depends on
them: every surface is rendered through Morpheus's own report and tab providers.
See [SECURITY.md](../SECURITY.md).

---

## The browser half

The graph is drawn client-side from a JSON payload embedded in the page. The
layer toggles, search, hop expansion and edge-label decluttering all operate on
data already in the browser — **none of them re-query anything.** Changing a
layer toggle costs nothing and cannot fail.

Every Perch asset announces its build number to the browser console:

```
[perch-asset] perch.js build 0.3.102 loaded and executed to completion
```

**That line is the only reliable way to tell a cached asset from a fix that did
not work.** Morpheus caches plugin assets and browsers cache them again; the two
are indistinguishable from every other angle.

---

## What Perch never does

- Write to Morpheus. Ever — no provisioning, no remediation, no state.
- Read a credential-bearing column. See [SECURITY.md](../SECURITY.md).
- Contact a host unless you enabled a host-telemetry layer.
- Contact anything outside Morpheus unless you configured it and supplied
  credentials.
- Install anything on a hypervisor. The one layer needing a package
  (`lldpd`) says so and leaves the decision to you.
