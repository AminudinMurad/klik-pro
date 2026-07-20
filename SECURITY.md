# Security Policy

## Supported versions

Klik PRO is distributed as rolling releases; only the **latest release** receives
fixes. Please reproduce any issue on the newest version before reporting.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Use GitHub's private vulnerability reporting instead: on the repository's
**Security** tab, choose **Report a vulnerability**. That opens a private advisory
visible only to the maintainer.

Please include:

- what you observed and why it's a security concern,
- steps to reproduce (and the Klik PRO version + macOS version),
- any relevant logs from `~/Library/Logs/klik-pro-*.log`.

You'll get an acknowledgement as soon as the maintainer is able; this is a
single-maintainer hobby project, so response times are best-effort.

## Scope & context

Klik PRO is a local macOS utility. It:

- requires the **Accessibility** permission to read the mouse's extra buttons
  (granted by you in System Settings), and
- is **not notarized** — it's ad-hoc signed, so macOS Gatekeeper will warn on a
  downloaded copy (this is expected; see the README's install steps).

The optional "Special Feature" launches other apps via small local wrapper scripts
on your machine. Klik PRO makes no network calls except an in-app **check for
updates**, which does a read-only request to the public GitHub Releases API.

## Release authenticity

The optional Terminal installer authenticates each official DMG checksum manifest
with a dedicated Ed25519 release key before it downloads or installs the app. It then
verifies SHA-256, bundle identities and versions, universal architectures, and the
ad-hoc code-signature integrity before requesting permission to remove quarantine.
The release-key fingerprint is:

```text
SHA256:Evg4ITqpPJY/aIT48Zv9Cp3psQfo977uCz/35a2k79E
```

The release-signing private key is not stored in this repository. A checksum file
downloaded beside a DMG is not trusted unless its `.sig` file verifies with this key.
The corresponding public key is published as `release-signing-key.pub`.
The signing tool also refuses a private-key file that is readable by group or other
users. The maintainer should keep a separate protected backup; losing this key means
existing installers cannot authenticate a newly signed release.
This protects against a release-asset replacement, but it does not make the app
Apple-notarized or remove the need for Accessibility approval.
