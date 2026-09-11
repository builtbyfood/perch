# Schema

What Perch reads, and what it assumes about your Morpheus database.

**This page exists so you can file a useful schema-difference issue.** If a layer
reports `degraded`, the banner names a table or column your Morpheus does not
have; this is the list to check it against.

> **Schema facts port; data facts do not.** Table and column names come from
> Morpheus's own data model and should hold on any 9.0 install. Everything about
> *what is in* those tables — how many rows, which type codes, which columns are
> populated — was observed on one appliance and may be wrong for yours. Where a
> row below says "observed", read it as a report, not a specification.

---

## How Perch degrades

Perch guards every column that is not promised on every Morpheus version. A
missing table or column produces a **named** `degraded` status, never an empty
layer, because "this data does not exist here" and "Perch could not read it" are
opposite instructions to an operator.

The appliance diagnostic's schema-drift section lists every such mismatch on your
install. That output is the single most useful thing to send from a Morpheus
version other than the one Perch was built against.

---

## Tables Perch reads

| Table | Used for | Notes |
|---|---|---|
| `compute_zone` | clouds | `deleted` guarded |
| `compute_zone_type` | cloud type | joined only where present; decides whether host telemetry can reach the cloud's hosts |
| `compute_server` | hosts and VMs | **no `deleted` column** — it has `enabled`/`managed`/`status`/`power_state` |
| `compute_server_type` | host-vs-VM, icons | the discriminator; see below |
| `compute_server_interface` | interfaces | **no server FK** — joined through `compute_server_compute_server_interface` |
| `network`, `network_type` | networks, glyphs | `network.type_id` guarded |
| `network_router`, `network_router_type`, `network_router_interface` | routers | router interfaces carry no address |
| `security_group`, `security_group_rule` | security groups | |
| `container`, `instance` | instance scoping, Kubernetes | |
| `compute_device`, `compute_device_type` | hardware devices | `deleted` guarded |
| `datastore`, `storage_volume` | datastores | the volume→datastore join does not carry on every integration |
| `backup`, `backup_result` | backup overlay | |
| `monitor_check`, `monitor_check_type`, `%monitor%` join tables | monitoring overlay | join tables are **discovered**, not assumed — see below |
| `scan_result` and related | compliance overlay | |
| `audit_log` | activity overlay | |
| `account`, `user` | attribution | |

---

## The discriminators

These are the values that decide how something is drawn. **They are the most
likely thing to differ on your install**, and the appliance diagnostic prints all
four.

### Host versus VM

A server is a **hypervisor** when its joined `compute_server_type` **name or code
contains the substring `hypervisor`**, case-insensitively.

Not a fixed list of codes. `compute_server.server_type` proved unreliable and
`compute_server.category` is NULL on observed rows, so neither is used.

Observed codes: `mvmHost` and `esxiHypervisor` match; `morpheusVm`,
`morpheusWindowsVm` and `esxiUnmanaged` do not.

**If your hypervisors render as VMs, this substring is why** — send the type list
from the diagnostic and it can be handled.

### Icons

`compute_server_type.code`, `network_type.code`, `network_router_type.code` and
`compute_device_type.code` each pick a glyph. **An unrecognised code falls back to
a generic glyph and a plain label, never to a specific one.**

That fallback is deliberate: a wrong answer that looks confident is worse than a
generic one that looks unremarkable. A `pci` device and an unidentified device
draw alike, because neither says what the hardware actually is.

### Kubernetes cluster type

`compute_server_group_type.code` identifies a Kubernetes cluster: any code
containing `kubernetes`, plus the managed flavours `eks-cluster`, `gke-cluster`
and `aks-cluster` whose codes do not contain the word.

**The list is not closed.** Perch logs every distinct group-type code it sees, so
a code it does not recognise appears in the log rather than being silently
excluded. If your clusters are not detected, that log line is what to send.

### Cloud type

`compute_zone_type.code` decides whether a cloud's hosts can be reached over SSH
at all. Cloud types known to be unreachable are excluded from host telemetry
**before** any connection is attempted, and the layer says so rather than timing
out four times.

An **unrecognised** cloud type is dispatched to, exactly as before — Perch does
not assume your platform cannot work simply because it has not seen it.

---

## Columns and tables that are not where you would expect

Each of these cost a release to find. They are recorded so the next reader does
not spend one confirming them.

| Expectation | Reality |
|---|---|
| `compute_server_type.category` | **Does not exist.** `container_type` has a `category`; the server type table does not. Host-vs-VM comes from the type's name or code containing `hypervisor`. |
| `container.namespace` | **Does not exist.** Nothing in `container` records a Kubernetes namespace, which is why the pod layer reports *unsupported* rather than rendering. |
| `compute_server.category` | Present, and NULL on every observed row — so it is not a usable discriminator even where it exists. |
| Security-group membership | **`security_group_association`**, not `compute_server_security_group`. The latter appears on no version probed. |
| Security-group attachment | **`security_group_location`** — `network_id` and `network_router_id`. |

### The association tables are empty here

Both `security_group_association` and `security_group_location` hold **zero rows**
on the verified appliance. That means the reference types they use are
**unobserved**, so Perch maps the ones it knows (`ComputeServer`, `Instance`,
`Container`, matched case-insensitively) and **names anything else** rather than
dropping it.

If your estate populates either table, the diagnostics script captures the
distinct values and that output is exactly what a schema-difference issue needs.

---

## Two things that are not assumptions

**Monitoring join tables are discovered.** Perch queries `information_schema` for
`%monitor%` tables and inspects their columns, rather than hardcoding a join path
that differs across versions.

**`compute_server_interface` has no server foreign key.** `ref_type`/`ref_id` are
vestigial NULLs; the link is a GORM join table. There is no `ip_address` column
on it either — addresses come from the server's `internal_ip`/`external_ip`.

---

## Filing a schema-difference issue

The `schema-difference` issue template asks for exactly what is needed. In short:

1. The `degraded` banner text — it names the table or column.
2. The schema-drift section of the appliance diagnostic.
3. Your Morpheus version.
4. The type-code lists, if a glyph or a host-vs-VM classification looks wrong.

**Review before sending.** The type lists name your clouds and servers. See
[SECURITY.md](../SECURITY.md).
