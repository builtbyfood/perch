# Configuration

Two places to configure Perch:

- **Plugin settings** — Administration → Integrations → Plugins → Perch → Edit. Global, apply to every surface, need a page reload.
- **Report run options** — the dialog shown by Operations → Reports → Perch → Run Now. Per-run, and they override nothing permanently.

The tabs have no run-options dialog, so their layer selection lives in plugin settings.

---

## What things cost

Every layer is labelled below with where its data comes from, because that is what determines its cost:

| Cost | Meaning |
|---|---|
| **Local SQL** | A query against the Morpheus database on the appliance. Fast. On by default. |
| **SSH** | A command run on each hypervisor via the Morpheus agent. Adds network latency per host, per layer. Off by default. |
| **External REST** | An HTTP call to a system outside Morpheus. Needs credentials. Off by default. |

**Everything that leaves the Morpheus database is off by default.** That is the whole rule.

---

## Layers

Each of these is a plugin setting (`Tabs — <layer>`, controlling the Instance and Server tabs) **and** a per-run report option. Defaults are the same in both.

| Layer | Cost | Default | What it adds |
|---|---|---|---|
| Security Groups | Local SQL | **on** | Security groups and their rules |
| Routers | Local SQL | **on** | Routers — T0/T1, VPC, VNet |
| Kubernetes | Local SQL | **on** | Pods and services |
| Compliance Overlay | Local SQL | **on** | Borders VM and host nodes by SCAP compliance tier |
| Backup Overlay | Local SQL | **on** | Glows VM and host nodes by backup coverage |
| Monitoring Overlay | Local SQL | **on** | Health-icon prefix on VM and host labels |
| Recent Activity Overlay | Local SQL | **on** | Badges recently-touched nodes with activity heat |
| Datastores | Local SQL | off | Datastores, and the volumes attaching servers to them |
| Hardware Devices | Local SQL | off | Assigned hardware devices — GPU passthrough and similar |
| Host Traffic Volume | **SSH** | off | Per-VM cumulative byte totals, via `virsh` |
| Active Host Flows | **SSH** | off | Live OVS datapath snapshot |
| Tracked Connections | **SSH** | off | Cluster mesh and storage, via OVS conntrack |
| Storage Paths | **SSH** | off | Multipath and iSCSI session paths |
| LLDP Neighbours | **SSH** | off | Switches and neighbours seen on the wire. **Also needs the `lldpd` package** — see the Install guide |
| Contrail Flows | **External REST** | off | Live Contrail VM-to-VM flows |
| Apstra Fabric | **External REST** | off | Physical fabric overlay |
| Historical Flow Replay | **External REST** | off | Time-slider replay of historical flows |

The overlays are the four that decorate existing nodes rather than adding new ones — they cost a query each and no extra graph.

### Sub-options

Some layers have a nested option, shown indented in the run dialog:

| Option | Default | Effect |
|---|---|---|
| Include **unassigned** devices too | off | Hardware Devices normally shows only devices assigned to a guest. Turning this on includes the full inventory, which is high-fanout on a host with many devices. |
| Also read libvirt for **observed passthrough** | off | Reads the hypervisor directly and draws passthrough Morpheus has not recorded, in its own edge style. **Needs the host-telemetry switch as well** — with it off, the devices layer is entirely database-derived and contacts no host. |
| Include Contrail flows | off | Adds Contrail as a source for the flow layer. |
| Include AWS VPC Flow Logs | off | Via the configured feed URL. |
| Include Azure NSG Flow Logs | off | Via the configured feed URL. |

---

## Report run options

Shown only in the report dialog, not in plugin settings:

| Option | Default | Effect |
|---|---|---|
| **Cloud** | blank = all | Restrict the report to one cloud. |
| **Include powered-off VMs** | on | Turn off for a graph of what is actually running. |

---

## Host telemetry

| Setting | Default | Effect |
|---|---|---|
| **Enable host telemetry** | off | Master gate for the SSH layers. Off because these are the only collectors that leave the appliance database. |
| **Enable LLDP neighbour discovery** | off | A **second, separate** master gate, for the LLDP layer only. Every other telemetry layer runs commands already present on an MVM hypervisor; LLDP needs a package installed. Enabling per-VM traffic volume must not implicitly consent to a package dependency, so the two are two questions. |
| **Also run host telemetry on the Instance/Server/Cluster tabs** | off | Separate gate. A report is run deliberately; a tab renders on every page view. A four-host cluster with three telemetry layers on makes twelve round trips. |
| **Per-host command timeout (seconds)** | 10 | How long to wait for one host to answer one command. |
| **Total wall-clock budget (seconds)** | 45 | Across all hosts **and all six telemetry phases in the run** — a total, not an allowance each. On exhaustion the collector stops dispatching and degrades, naming the hosts it never reached. |

When telemetry is off, tabs say so explicitly — an absent layer is never presented as an empty one.

---

## Thresholds and windows

| Setting | Default | Effect |
|---|---|---|
| **Backup fresh threshold (hours)** | 25 | A server whose last successful backup is older than this is flagged stale. |
| **Activity lookback window (minutes)** | 60 | How far back to look for recent activity. Within the window: HOT ≤ 5 min, WARM ≤ 30 min, otherwise COOL. |
| **Activity types** | blank = all | Comma-separated filter on what counts as activity, e.g. `provision,reconfigure,remove,resize`. |
| **Exclude object classes** | `kvm,terminal` | Audit-log object classes to drop as noise. The default filters infrastructure polling and terminal resizes, which dominate the log on a KVM appliance. **A VMware or Nutanix appliance will need different values** — blank excludes nothing. |
| **Exclude event types** | blank | Substring match on audit-log event types, e.g. `terminal,resize`. |
| **Medium failures that escalate to "high"** | 20 | A completed SCAP scan with more than this many failed medium-severity rules is tiered high. |
| **Drop datapath flows below this many bytes** | 1024 | Noise filter on the flow layer. Unfiltered, a datapath dump does not merely add noise — it actively misleads. |

## Search

| Filter | Values |
|---|---|
| `compliance:` | `critical`, `high`, `medium`, `low`, `pass`, `unscanned` |
| `backup:` | `protected`, `stale`, `failing`, `unprotected` |
| `health:` | `healthy`, `warning`, `error`, `muted`, `pending`, `uncovered` |
| `active:` | `hot`, `warm`, `cool` |
| `group:` | any node group — `vm`, `host`, `network`, `router`, … |
| `lldp:` | `switch`, `router`, `wireless`, `phone`, `station`, `virtual`, `unresolved` |
| `switchport:` | free text over the resolved remote port label |
| *(plain text)* | matches label and tooltip |

Space-separated terms **AND**; repeating a key **ORs** its values. **Prefix any term with `-` to exclude it** — `-group:vm`, `group:vm -compliance:pass`, `-web01`. A query of only exclusions matches everything not excluded.

An unrecognised filter key matches nothing rather than everything, so a typo returns an empty result instead of the whole graph.

The counter reads `3 matches, 11 shown` — the second number is what neighbour expansion brought in, so it moves with the hop control.

## Edge labels

| Control | Default | Effect |
|---|---|---|
| **Edge labels** | computed | Shows the text on edges. Starts **off** when the graph carries more than roughly 15 **labelled** edges and on below that — an unlabelled edge cannot clutter, so only labelled ones are counted. |

Toggling is an override and sticks for the session. With labels off, hovering a node reveals its own edges' labels, and an active search keeps labels on whatever it matched.

## Layout

| Setting | Default | Effect |
|---|---|---|
| **Clamp the fit below this zoom scale** | 0.12 | A fit that frames a far outlier shrinks everything interesting to a speck. Below this scale Perch frames the focus instead and says so, with a control to restore the full view. Raise it if the clamp fires when it should not; set it to 0 to disable clamping entirely. |

This is a threshold, not a constant — what counts as unreadable depends on your viewport and node count.

## Scope tier

Controls how wide a scoped surface (instance, server, cluster, network) collects:

| Tier | Collects |
|---|---|
| Focus only | Just the subject and its direct attachments |
| Observed links | Plus peers with observed traffic |
| Shared network | Plus everything sharing a network with the subject |

Wider tiers produce larger graphs and slower renders. The control is present on every scoped surface; on surfaces where every node is already a focus node it is correct but inert, and says so.

---

## External systems

All optional, all off until configured. Credentials come from **Administration → Trust**, referenced by numeric ID.

### Contrail

| Setting | Notes |
|---|---|
| Contrail Analytics URL | e.g. `https://contrail-analytics.example.com:8081` |
| Contrail Config API URL | e.g. `https://contrail-api.example.com:8082` |
| Contrail credential (Trust ID) | Numeric ID of a stored credential. Accepts `api-key` or `username-password`. |
| Contrail flow limit | Default 200. Maximum records fetched. |

### Apstra

| Setting | Notes |
|---|---|
| Apstra URL | e.g. `https://apstra.example.com` |
| Apstra credential (Trust ID) | Numeric ID. Accepts `username-password` only. |
| Apstra Blueprint ID | Blank = all blueprints. |

### Historical flow replay

| Setting | Default | Notes |
|---|---|---|
| History window (hours) | 24 | How far back to fetch flow records for the time slider. |
| Bucket size (minutes) | 5 | Slider resolution. Smaller = more precision and more data in the UI. |
| History max distinct pairs | 500 | Safety cap. Only the top-N source/destination pairs by bytes are kept. |
| AWS / Azure flow feed URL | blank | A URL — typically a small Lambda, API Gateway or Azure Function proxy — that runs the cloud's own log query and returns normalised flow JSON. Accepts `?start=` and `?end=` microsecond timestamps. |

**Blank is a valid state.** An unconfigured external layer reports as not configured, which is different from broken and different from empty.

> The **Cypher path** fields for Contrail, Apstra and the flow feeds are legacy and non-functional. Use the credential (Trust ID) fields instead, and leave the Cypher paths blank.

### TLS

| Setting | Default | Effect |
|---|---|---|
| **Trust all TLS certs (LAB ONLY)** | false | Disables certificate verification for the external REST calls above. As labelled: for lab use. Leave it off anywhere that matters. |
