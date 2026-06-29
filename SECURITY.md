# Security

## Supported Use

ClipLAN is intended for personal use on trusted Macs and trusted local networks.

## Reporting Issues

If this project is published on GitHub, please report security issues privately through GitHub Security Advisories when enabled. If advisories are not enabled yet, open a minimal issue that says a security report is available without including exploit details.

## LAN Sync Boundary

LAN sync uses a shared pairing code to decide whether peers may exchange clipboard entries. The pairing code is hashed before being sent over the wire, but the LAN protocol is not a replacement for a full end-to-end encrypted trust system.

Avoid enabling LAN sync on public, hostile, or untrusted networks.

## Sensitive Clipboard Content

Clipboard managers can capture sensitive data such as passwords, tokens, private messages, images, file paths, and customer or personal information. ClipLAN provides local storage and local deletion behavior, but it cannot know which clipboard items are sensitive.

Review your history before sharing logs, screenshots, databases, payload folders, or bug reports.

## Signing And Distribution

Local development builds are signed ad-hoc by default. Public binary releases should be signed with a Developer ID Application certificate and notarized. Public `.pkg` releases additionally require a Developer ID Installer certificate.
