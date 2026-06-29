# Contributing

Thanks for your interest in ClipLAN.

## Development

```bash
./script/build_and_run.sh
```

The project uses SwiftPM and targets macOS 14 or later. The run script builds the app, stages `dist/ClipLAN.app`, signs it ad-hoc unless `CODE_SIGN_IDENTITY` is set, and launches it.

## Guidelines

- Keep changes small and focused.
- Prefer native macOS APIs and SwiftUI/AppKit patterns already used in the project.
- Do not add new dependencies unless they clearly reduce complexity.
- Do not include real clipboard databases, payload files, screenshots with private data, signing certificates, provisioning profiles, or local keychains.
- Update `README.md`, `PRIVACY.md`, or `SECURITY.md` when behavior changes user data handling, permissions, LAN sync, or distribution.

## Testing

Run the available tests when SwiftPM is available:

```bash
swift test
```

For UI or packaging changes, also run:

```bash
./script/build_and_run.sh --verify
```
