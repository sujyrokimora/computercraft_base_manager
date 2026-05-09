# ComputerCraft Network System README

## Commands

### Help

```text
help
help reactor
help battery
help update
```

### List

```text
list
list <group>
```

Examples:

```text
list reactor
list power
list farm
```

### Status

```text
status
status <group>
```

Examples:

```text
status reactor
status power
status farm
```

### Watch

Live refresh status once per second.

```text
watch
watch <group>
```

Examples:

```text
watch reactor
watch power
```

Stop with `CTRL+T`.

### Battery

```text
battery
battery power
```

### Generic Nodes

```text
<group> <target> on
<group> <target> off
<group> <target> status
<group> <target> update
```

Examples:

```text
farm alloy_X on
farm all off
lights base on
pump water off
```

### Reactor

```text
reactor <name> on
reactor <name> off
reactor <name> status
reactor <name> reset
reactor <name> burn <rate>
reactor <name> update
```

Examples:

```text
reactor main on
reactor main off
reactor main reset
reactor main burn 2.5
reactor all status
```

If auto SCRAM triggers:

- reactor cannot be turned on
- burn rate cannot be changed
- matrix auto-start cannot restart it

Only this unlocks it:

```text
reactor <name> reset
```

### Update

```text
update server
update <group>
```

Examples:

```text
update server
update reactor
update power
update farm
```

Nodes download latest files from `manifest.lua` and reboot.

## Matrix Multi-Reactor Support

During matrix setup you can assign reactors:

```text
alpha,beta
```

Then that matrix controls only those reactors.

Blank assignment means the matrix controls all reactor nodes.

Matrix automation:

- `<= 20%` battery: sends reactor ON request once
- `>= 80%` battery: sends reactor OFF request once

## Status Meanings

```text
ON
OFF
LOCK
OFFLN
```

- `ON`: machine is active
- `OFF`: machine is inactive
- `LOCK`: reactor safety lockout is active
- `OFFLN`: server has not received heartbeat for 30 seconds
