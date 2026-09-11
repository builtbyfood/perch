# Feedback

Perch is in beta. This page says what we want back, why that particular thing,
and how to send it without publishing your infrastructure to a public issue
tracker.

---

## The one thing to understand first

**Perch has been developed and verified against exactly one environment.**

One Morpheus 9.0 appliance. One private cloud. Four KVM/MVM hypervisors on Open
vSwitch. Eleven servers, five networks.

Every threshold in this plugin, every default layer selection, every type-code
mapping that picks an icon, every fanout guard and every timeout budget was
chosen by looking at that estate and picking a number that worked there. None of
them has ever been checked against a second one.

That is not a disclaimer bolted onto the bottom of a README. It is the entire
shape of the problem, and it determines what feedback is valuable.

---

## Why "it worked" is as valuable as a bug report

Nobody opens an issue when software works. That instinct is right almost
everywhere and wrong here.

A bug report tells us one thing is broken. **A working run with numbers attached
tells us which of the hundred guesses in this plugin happened to generalise** —
and that is the question the beta exists to answer. There is no other way to
learn it. We cannot find it from here; we have one estate and it agrees with
itself.

Concretely, a report that says *"VMware, 140 servers, 22 networks, 3 clouds,
multi-tenant, everything drew, Datastores was empty and I expected that, took
about 25 seconds"* moves this project further than a stack trace. It converts
five tuned-for-one numbers into verified ones, and it is five minutes of your
time.

So: **[`it-worked.yml`](../../issues/new?template=it-worked.yml)** exists, it is
prompted at the moment of success rather than failure, and filling it in is not
a courtesy.

---

## What is most valuable, in order

1. **A working run, with your numbers.** Above. The rarest and the most useful.
2. **Schema and type-code differences.** Which cloud, server, network and router
   type codes your Morpheus uses; which guarded columns exist; anything the
   diagnostic flagged as drift. These decide every glyph and the
   host-versus-VM classification, and a type code Perch has not seen falls back
   to a generic glyph rather than failing — so this class is *silent* by design.
3. **Anything that looked wrong but did not error.** A wrong count, an odd
   glyph, a node in the wrong inventory table, a host drawn as a guest. Nothing
   reports this, because from the code's point of view nothing went wrong. It is
   the hardest class to catch and the most likely to exist on an estate that is
   not ours.
4. **Errors and crashes.** Genuinely last — not because they do not matter, but
   because they already announce themselves. Perch is deliberately loud: a layer
   that failed says so, with a reason, in a banner and in the log. Those are the
   reports that need us least.

**VMware in particular.** The ESXi handling shipped in 0.3.87 is unit-tested and
has **never been run against a live ESXi cloud** — see
[Limitations §14](LIMITATIONS.md). If you are pointing Perch at
VMware-managed Morpheus you are the first, and anything you see is worth
sending, including it simply working.

---

## Which form to use

| Situation | Form |
|---|---|
| It drew your estate | [It worked — here are my numbers](../../issues/new?template=it-worked.yml) |
| A layer is empty | [A layer rendered empty](../../issues/new?template=layer-empty.yml) — walks three checks first; two of them often close it |
| Your type codes or columns differ | [My schema or type codes differ](../../issues/new?template=schema-difference.yml) |
| Something is drawn wrongly, or not drawn | [Bug report](../../issues/new?template=bug.yml) |
| Anything else | A blank issue. They are enabled on purpose. |

Before filing anything except the first, it is worth reading
[Limitations](LIMITATIONS.md) and [Troubleshooting](docs/TROUBLESHOOTING.md)
— several of the commonest reports are answered there, and an empty layer with
zero rows behind it is correct rather than broken.

---

## Collecting the diagnostic

Almost every form asks for `/tmp/perch-diag-appliance-*.txt`. Run a report
first, so there is something in the log, then:

```bash
chmod +x perch-diag-appliance.sh
sudo ./perch-diag-appliance.sh
```

[Diagnostics](docs/DIAGNOSTICS.md) describes all three scripts — what each
collects, where it writes, and what to do with the output.

---

## Redaction

### What is identifying in the output

The diagnostics describe your estate. Expect to find, and to look at before
posting:

| Where | What |
|---|---|
| Appliance diagnostic | hostnames, IPv4 and IPv6 addresses, MAC addresses, cloud names, server and VM names, network names and CIDRs, datastore names, cluster and pool names, usernames in audit rows |
| Hypervisor diagnostic | the host's own hostname and addresses, MAC addresses, libvirt domain (VM) names, bridge and interface names, iSCSI portal addresses, LUN and WWN identifiers, multipath device names |
| LLDP sections | neighbour switch names, chassis identifiers, port descriptions — often the most operationally revealing thing in the file, because switch port labels are written by humans and say what the link is for |
| Browser console output | node identifiers, which encode names |

None of this is secret. All of it is real, and a public issue tracker is public.

### What the scripts never collect

The diagnostics deliberately select **no credential-bearing column**. These five
are excluded by construction, in every query, in both scripts:

```
config            ssh_password      raw_data      last_stats      service_password
```

They hold encrypted secrets, connection strings and cached payloads, and no
Perch diagnostic reads any of them. You do not need to check the file for
passwords — there are none. You need to check it for **identity**, which is a
different job and the one that is actually left to you.

<a name="redacting-without-destroying-the-value"></a>
### Redacting without destroying the value

The instinct is to blank everything. Resist it: a file with every name replaced
by `XXXX` is unreadable and undiagnosable, and you will have done the work for
nothing.

**Keep the shape, replace the identity.**

- **Substitute consistently.** `kvm-01` must become `host-a` *everywhere it
  appears* — in the log lines, the flow output, the LLDP neighbour list and the
  database survey alike. Half the diagnostic value is in seeing that the same
  host appears in two places; inconsistent renaming destroys that and looks like
  a bug in Perch.
- **Keep every count and every number.** Row counts, node and edge counts,
  timings, budgets. These identify nothing and are most of what we read.
- **Keep type codes verbatim.** `compute_zone_type.code`,
  `compute_server_type.code`, network and router type codes. These are the
  finding in a schema report — renaming them removes the only thing it
  contained.
- **Keep the structure of addresses.** `10.20.30.41` → `10.20.30.41` is fine if
  RFC1918 space is not sensitive to you; if it is, map subnets consistently
  (`10.20.30.0/24` → `10.0.1.0/24`) and keep the host octets distinct. Whether
  two hosts are on the same subnet is frequently the answer.
- **Keep the banner and error text exactly.** It is generated from what the
  collector did, so its precise wording identifies a code path. A paraphrase
  does not.

A consistent substitution across a whole file is one command:

```bash
sed -e 's/kvm-0/host-/g' \
    -e 's/prod-vc01/vcenter-a/g' \
    -e 's/\bacme\b/example/gI' \
    /tmp/perch-diag-appliance-*.txt > /tmp/perch-diag-redacted.txt
```

Then read `/tmp/perch-diag-redacted.txt` before attaching it. The `sed` catches
what you predicted; the read catches what you did not.

### If it cannot be redacted

Some faults can only be explained with detail you are not willing to publish.
That is a normal outcome and not a reason to drop the report. **Open the issue
with the shape of the problem and say that the detail is sensitive** — we will
find another route rather than lose the finding.

---

## What this is, and what to expect

Perch is a community plugin. It is **not an HPE or Morpheus product**, it is not
supported by HPE, and there is no service-level anything behind this page. It is
Apache-2.0 licensed and distributed as a binary; see [NOTICE](NOTICE).

Issues are read. Not all of them become changes — particularly requests to make
a number configurable that is currently a constant, since every such number is
one more thing that has only ever been correct on one estate. But a report that
is not acted on still lands in the record of what a second estate looked like,
and that record is the point.
