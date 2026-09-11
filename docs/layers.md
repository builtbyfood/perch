# Perch — what each layer shows

Each layer is independently toggleable. This page says where its data comes
from, what it draws, and — the part that matters most — **why it might
legitimately be empty**.

> A layer that found nothing tells you why. *Could not look* and *nothing there*
> are different findings, and Perch never renders one as the other.

Layer names in the interface carry an internal phase number in some cases
(`Datastores (19)`). Those numbers mean nothing outside the project and are
omitted here.

## Core

**Source:** Morpheus database  
**Default:** on where it is the subject of the surface

Clouds, hosts, VMs, networks and the edges between them. The base every other layer decorates.

*Why it might be empty:* Never empty on a working appliance. If it is, the surface reports `degraded` with the query fault rather than drawing an empty graph.

## Security Groups

**Source:** Morpheus database  
**Default:** on where it is the subject of the surface

Security groups and the cloud they belong to, with their rules in the tooltip.

*Why it might be empty:* Empty where no security groups are defined, or where this Morpheus tier does not have them.

## Routers

**Source:** Morpheus database  
**Default:** on where it is the subject of the surface

Routers, the networks they serve, and router-to-router hierarchy.

*Why it might be empty:* Router interfaces carry no address in the database, so a gateway seen in traffic resolves as an external endpoint rather than to its router node.

## Kubernetes

**Source:** Morpheus database  
**Default:** on where it is the subject of the surface

Namespaces, services and pods, edged to the cluster that runs them.

*Why it might be empty:* Absent entirely on tiers without Kubernetes — the control renders disabled with the reason, not merely unticked.

## Contrail Flows

**Source:** External REST  
**Default:** off — it leaves the appliance database

Flow records from a Contrail analytics endpoint.

*Why it might be empty:* Configured but unauthenticated until credentials are supplied. Unexercised against a live Contrail install.

## Apstra Fabric

**Source:** External REST  
**Default:** off — it leaves the appliance database

Fabric blueprints, spines, leaves and the servers beneath them.

*Why it might be empty:* Unexercised against a live Apstra install.

## Historical Flows

**Source:** External REST  
**Default:** off — it leaves the appliance database

Replayed flow history, with a time slider.

*Why it might be empty:* Distinct from Active Host Flows by design: live datapath traffic is a snapshot and must never feed a cumulative store.

## Hardware Devices

**Source:** Morpheus database  
**Default:** on where it is the subject of the surface

PCI and USB inventory per host, with assigned devices edged to the guest holding them.

*Why it might be empty:* On the estate this was built against, 76 device nodes for 11 servers — which is why it is off by default on the report and on by default only where the devices are the subject.

## Datastores

**Source:** Morpheus database  
**Default:** on where it is the subject of the surface

Datastores as nodes, with one edge per server-to-datastore pair carrying the volume count and drive detail.

*Why it might be empty:* A datastore pinned to one host by `host_id` is drawn as PER-HOST and labelled with its owner: other hosts reach it through the local datastore pool, but the bytes are not shared and the capacity is not additive.

## Storage Paths

**Source:** Hypervisor, over the agent  
**Reads:** `multipath -ll · iscsiadm -m session -P 3`  
**Default:** off — it leaves the appliance database

LUNs, their paths, path health, and the iSCSI portals and targets behind them.

*Why it might be empty:* Empty on a host with no multipath or iSCSI stack — a valid result, reported as such rather than as a failure. Where the host and the database disagree about paths, the host is authoritative: Morpheus inventories individual SCSI paths as separate volumes and does not do so everywhere.

## Active Host Flows

**Source:** Hypervisor, over the agent  
**Reads:** `ovs-appctl dpctl/dump-flows`  
**Default:** off — it leaves the appliance database

Live guest datapath traffic, as MAC-to-MAC pairs with byte counts.

*Why it might be empty:* A live snapshot only — the datapath cache evicts idle flows after roughly ten seconds. Expect it to be small, and expect it to differ between runs.

## Tracked Connections

**Source:** Hypervisor, over the agent  
**Reads:** `ovs-appctl dpctl/dump-conntrack`  
**Default:** off — it leaves the appliance database

Tracked connections, classified by port role: storage, cluster control plane, management, and uncategorised.

*Why it might be empty:* Guest traffic is not conntracked, so every edge here belongs to the hypervisor. On a guest surface it is the machine's context, not its own connections.

## Defaults are per surface

A layer is on by default only where it is the **subject** of the surface it is
drawn on. Hardware devices are on for a host — they are that host's — and off
on the estate report, where they are nobody's subject and 76 of them ring the
graph.

Anything that leaves the Morpheus database is off everywhere, whatever the
surface, and that rule wins over subject-hood.

| Surface | On by default |
|---|---|
| Report | Core, Routers, Security Groups |
| Cluster | Core, Routers, Datastores |
| Server / host | Core, Routers, Datastores, Hardware Devices |
| Instance / VM | Core, Routers, Datastores |
| Network | Core, Routers, Security Groups |

Every layer stays selectable on every surface. This changes only where each
one starts.
