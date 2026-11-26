---
name: cisco-small-business-switch-ops
description: "Use when resetting, upgrading firmware on, addressing or bundling ports on a Cisco 250 Series small business smart switch (SG250, SF250, CBS250), or when asking what firmware one runs, whether a downgrade is allowed, how to factory reset it, how to set a static management address, or how to form a LACP port channel on it. Trigger phrases: SG250, SF250, CBS250, Cisco 250 Series, factory reset a Cisco small business switch, Reset button hold time, Firmware Operations, swap image, active image after reboot, channel-group mode auto, interface vlan 1 ip address, downgrade prevented, 2.5.9 release notes, old switch config reappears after reset. NOT for Catalyst IOS-XE switches (multi-vendor-network-ops, napalm-netmiko) or the 350X and 550X stackable lines beyond what their shared release notes state."
metadata:
  version: 1.0.0
---

# Cisco 250 Series small business switch operations

> **Skill marker**: when applying this skill, begin your reply with `[skill: cisco-small-business-switch-ops]`
> on its own line.

## Overview

The 250 Series smart switches (SG250 gigabit, SF250 fast Ethernet, and the CBS250 successor) are managed by a web GUI and a
small IOS-like CLI. Their documents are old and spread over three places: the Administration Guide, the CLI Guide and the
release notes. This skill holds what those documents say, what they do NOT say, and the cautions that cost time. **Version
stamp:** Administration Guide (page updated 2021-03-05, release path 2.5.7), CLI Guide pages updated 2025-02-28 (no release
named), release notes up to software 2.5.9.55 (January 2026), read 2026-11-26. Confirm each step on the switch with `?`; the
CLI guide names no release.

## Rules

1. **Reset with the switch off every network.** Power on, hold the Reset button for more than 10 seconds (under 10 seconds is only a
   reboot). Cisco says to disconnect the switch from the network, or disable all DHCP servers, first. The switch then answers at
   its factory address `192.168.1.254/24` with the vendor default login (published in the Administration Guide), which must be
   changed at first login. A community post says some firmware needs 15 to 20 seconds and one user saw the old configuration come
   back; confirm the old address no longer answers.
2. **A used switch may carry another network's configuration and address.** Reset before any cable, or it can clash with a live device.
3. **Read the version, then upgrade, then configure.** GUI: Administration, File Management, Firmware Operations shows "Active
   Firmware Version" (no CLI command was found). The switch keeps two images; Update Firmware (HTTP or HTTPS upload, or USB) writes the
   new one, you make it active and reboot from Administration, Reboot. Swap Image is the back-out. A reboot loses an unsaved running
   configuration, and some builds can reset the startup configuration, so upgrade a freshly reset switch.
4. **Check the release notes for the target before upgrading.** What the 2.5.9.x notes state: 2.5.9.16 fixed several unauthenticated
   buffer-overflow, denial-of-service and configuration-reading issues; 2.5.9.54 fixed passwords shown in clear text in the running
   configuration and added the HttpOnly cookie (after a downgrade below it, clear browser cookies to reach the GUI); 2.5.9.13 removed the
   `diffie-hellman-group-exchange-sha1` SSH key exchange and added SHA-2 ones, which can break an old SSH client or backup tool.
5. **Downgrades are restricted by model.** Boards from 2.4.5.x on carry a newer PoE chipset; the notes say a downgrade from 2.4 is
   prevented completely on the SG250-10P and SG250-26HP/P, and other SKUs can go back only to a stated floor (the SG250-50HP to 2.3.5).
   Treat an upgrade as one-way and pick the target once.
6. **Static management address (CLI Guide, IP Addressing Commands):** `interface vlan 1`, then `ip address <address> <mask>` (or a
   prefix length), then `ip default-gateway <address>` in global configuration. A static address stops a DHCP client on that interface.
7. **Port channel (CLI Guide, Port Channel Commands):** in the interface mode of each member, `channel-group <port-channel> mode {on | auto}`;
   `on` joins without LACP, `auto` joins through LACP. In `auto`, if no LACP messages arrive on any candidate port one port joins, and
   leaves when the first LACP message arrives, so verify the bundle from the far end instead of assuming it formed. The page found no
   separate command to create the port channel.
8. **Do not invent commands.** The pages found gave no save command, no `shutdown` form for a port and no CLI way to read the version.
   Confirm those on the switch, and write "not found in the sources read" rather than a command from memory.
9. **Lifecycle.** A search summary of Cisco's product page gave end of sale 2022-07-30 and end of support 2027-07-31 for the 250 Series;
   it was not checked on the lifecycle page, so verify before buying new units. The download is from Cisco's software site; whether it
   needs a login or contract was not stated.

## Red flags

- A used switch connected to a network before a factory reset.
- A firmware change on a switch that holds configuration nobody has backed up.
- A downgrade planned on a switch whose notes forbid it.
- A save, shutdown or version command written from memory into an instruction for someone else.
- An SSH backup or management tool failing right after an upgrade (the key exchange list changed in 2.5.9.13).
- A port channel called "up" because one member is up, with LACP in `auto` mode and no check from the far end.

## Bottom line

Reset off the network, read the version, upgrade a clean switch to the newest build the notes allow (it is one-way), then set the
address and the channel group, and verify the bundle from the other end. Say "not found" for any command the Cisco pages did not give.
