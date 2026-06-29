# Privacy

ClipLAN is local-first. It is built to keep clipboard data on your Mac unless you explicitly enable LAN sync.

## Local Data

ClipLAN stores clipboard metadata in SQLite and larger payloads as files under:

```text
~/Library/Application Support/ClipLAN
```

Stored data may include copied text, URLs, HTML, RTF, image payloads, file references, source application names, OCR text, favorites, pins, and timestamps.

## OCR

Image OCR uses Apple's Vision framework on the local Mac. OCR results are stored locally so image text can be searched. ClipLAN does not send images or OCR text to a cloud service.

## LAN Sync

When LAN sync is enabled, ClipLAN advertises and discovers peers through Bonjour and exchanges clipboard metadata and payloads over local TCP connections.

- Devices must use the same pairing code to exchange data.
- Small payloads may be sent inline.
- Larger payloads are requested on demand.
- LAN sync is intended for trusted local networks.

The pairing code helps avoid accidental cross-device sync, but it should not be treated as a strong security boundary on hostile or public networks.

## Cloud Services

ClipLAN does not include cloud sync, analytics, telemetry, advertising SDKs, or external API calls.

## Permissions

ClipLAN may request macOS Accessibility permission when auto paste is enabled. This permission is used to send the `Command + V` keyboard shortcut after writing the selected item to the system pasteboard.

Without Accessibility permission, ClipLAN still copies selected history items to the system pasteboard so you can paste manually.
