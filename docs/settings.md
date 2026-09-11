# Perch — settings reference

**Administration → Integrations → Plugins → Perch → Edit.**

Every setting below is read from the plugin's own definitions, so this page and
the dialog cannot drift apart. Settings are **global** and take effect on the
next page load — Perch never caches them per user or per surface.

A blank default means the feature is inactive until a value is supplied.

## Scope and collection

| Setting | Default | Type | What it does |
|---|---|---|---|
| **Fit Minimum Scale** | `0.12` | Text | A fit that frames a far outlier shrinks the interesting nodes to a speck. |
| **Scope Tier** | `linked` | Select | How much of the estate a scoped topology COLLECTS. off = the focus server, its parent/children, its networks, routers, cloud and devices. linked (default) = plus peers with an observed link — a live datapath flow (live datapath flows) or a historical flow (historical flows); a shared subnet is not a link. network =… |

## Host telemetry

| Setting | Default | Type | What it does |
|---|---|---|---|
| **Host Telemetry Enabled** | `false` | Checkbox | Master gate for BOTH host-telemetry phases. Off by default: these are the only collectors that leave the Morpheus database and reach hypervisors over SSH, adding network latency to every run. Privilege comes from the Morpheus agent, which on a default install already holds unrestricted NOPASSWD… |
| **Host Telemetry On Tabs** | `false` | Checkbox | Off by default, and separate from the master switch above. A tab renders on every page view: a four-host cluster with Phases 17, 18 and 21 on makes TWELVE SSH round trips, three independent 45-second budgets, and can take two minutes. The report is run deliberately and keeps whatever the master… |
| **Host Command Timeout Seconds** | `10` | Number | How long to wait for one hypervisor to answer one command. |

## Layers and phases

| Setting | Default | Type | What it does |
|---|---|---|---|
| **Trust All Certs (LAB)** | `false` | Checkbox | Trust all TLS certs (LAB ONLY) |
| **History Window (Hours)** | `24` | Number | How far back to fetch flow records for the time slider |
| **History Max Edges** | `500` | Number | Safety cap. Only the top-N source/dest pairs by bytes are kept. |
| **Host Command Total Budget Seconds** | `45` | Number | On exhaustion the collector stops dispatching and degrades, naming the hosts it never reached. A report that hangs is worse than a report missing a layer. |

## Thresholds and windows

| Setting | Default | Type | What it does |
|---|---|---|---|
| **Contrail Flow Limit** | `200` | Number | Contrail flow limit (max records) |
| **History Bucket (Minutes)** | `5` | Number | Time slider resolution. Smaller = more precision, more UI data |
| **Compliance Med-Fail High Threshold** | `20` | Number | A completed SCAP scan with more than this many failed medium-severity rules is tiered "high". Default 20. |
| **AWS Flow Feed URL** | `—` | Text | Optional. A URL (typically a small AWS Lambda / API Gateway proxy) that runs a CloudWatch Logs Insights query on your behalf and returns normalized flow JSON. Accepts ?start=&end= microsecond timestamps. |
| **AWS Flow Feed Auth Cypher Path** | `—` | Text | AWS flow feed Authorization (Cypher path) |
| **Azure Flow Feed URL** | `—` | Text | Optional. A URL (typically an Azure Function or App proxy) that runs a Log Analytics KQL query and returns normalized flow JSON. Accepts ?start=&end= microsecond timestamps. |
| **Azure Flow Feed Auth Cypher Path** | `—` | Text | Azure flow feed Authorization (Cypher path) |
| **Backup Fresh Hours** | `25` | Number | A server whose last successful backup is older than this is flagged as stale. |
| **Activity Window (Minutes)** | `60` | Number | How far back to look for recent activity on nodes. HOT ≤ 5 min, WARM ≤ 30 min, else COOL. |
| **Activity Type Filter** | `—` | Text | e.g. provision,reconfigure,remove,resize — filters what counts as "recent activity" |
| **Activity Exclude Object Classes** | `kvm,terminal` | Text | audit_log object_class values to drop as noise. Default filters KVM infra polling + terminal resizes (13k of 18.6k rows here); a VMware/Nutanix appliance will differ. Blank = exclude nothing. |
| **Activity Exclude Event Types** | `—` | Text | audit_log event_type substrings to drop, e.g. terminal,resize. Blank = exclude nothing. |
| **Flow Minimum Bytes** | `1024` | Number | Part of the non-optional noise filter. Unfiltered, the datapath dump does not merely add noise — it actively misleads. |
| **Flow Require Both Endpoints** | `true` | Checkbox | On (default): a datapath row is drawn only when both MACs resolve to Morpheus servers. CORRECTED 2026-07-27: the empty layer seen on this estate was NOT "no traffic exists" — a live run parsed 68 rows, 56 fell to the noise filter, and all 12 survivors were dropped because Perch could not name… |
| **Flow Show External** | `false` | Checkbox | Only applies when strict mode is off. Collapses ALL unresolved MACs into a single node: the gateway MAC alone appears in dozens of rows, so one node per unresolved MAC produces a hairball. |
| **Auto-Refresh Minutes** | `0` | Number | Client-side page reload cadence. Freshness of data still depends on a scheduled Morpheus Job re-running the report — see README. |
| **Stale Warn Minutes** | `60` | Number | Warn if data older than (minutes) |
| **Stale Critical Minutes** | `240` | Number | Mark as critically stale after (minutes) |

## External systems

| Setting | Default | Type | What it does |
|---|---|---|---|
| **Contrail Analytics URL** | `—` | Text | e.g. https://contrail-analytics.example.com:8081 |
| **Contrail Config API URL** | `—` | Text | e.g. https://contrail-api.example.com:8082 |
| **Contrail Auth Token Cypher Path** | `—` | Text | e.g. secret/contrail/analytics-token |
| **Apstra URL** | `—` | Text | e.g. https://apstra.example.com |
| **Apstra Username Cypher Path** | `—` | Text | e.g. secret/apstra/user |
| **Apstra Password Cypher Path** | `—` | Text | e.g. secret/apstra/pass |
| **Apstra Blueprint ID** | `—` | Text | Apstra Blueprint ID (blank = all) |
| **Contrail Credential ID** | `—` | Number | Numeric ID of a stored credential from Administration -> Trust. Accepts type api-key or username-password. Blank means not configured, which is a valid state — the layer is off rather than broken. Perch reads the credential in-process; the REST endpoint /api/credentials/{id} masks secrets and is… |
| **Apstra Credential ID** | `—` | Number | Numeric ID of a stored credential from Administration -> Trust. Accepts type username-password only. Blank means not configured. Supersedes the Cypher path fields above, which never worked: cypher.read(String) does not exist in this plugin API and every Cypher-backed secret resolves to null. |

## What the telemetry layers cost

The four agent-read layers each open an SSH session per hypervisor. On a
four-host cluster that is twelve round trips for a full run, which is why they
are off by default and why the tab switch is separate from the master one — a
report is run deliberately, a tab render is not.

| Layer | Command | Per host |
|---|---|---|
| Host Traffic Volume | `virsh domstats --interface` | 1 |
| Active Host Flows | `ovs-appctl dpctl/dump-flows` | 1 |
| Tracked Connections | `ovs-appctl dpctl/dump-conntrack` | 1 |
| Storage Paths | `multipath -ll`, `iscsiadm -m session -P 3` | 2 |

Every command is read-only. Perch never writes to a host.

## Privilege

Perch runs each command unprivileged first and only escalates if the output is
empty, so a host that permits the command outright is never asked for `sudo`.
Where escalation is needed, grant it **per command** rather than by wildcard —
a `virsh` wildcard in a sudoers entry is a privilege grant far wider than this
plugin needs.

If a command is denied, the layer reports `degraded` and names the host and the
command. It does not report empty: *could not look* and *nothing there* are
different findings, and conflating them is the failure this project has spent
the most effort avoiding.
