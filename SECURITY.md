# Security Policy

## Supported versions

Only the latest minor release line receives fixes. Older versions may be patched at the maintainer's discretion.

| Version | Supported |
|---------|-----------|
| 2.3.x   | yes       |
| < 2.3   | no        |

## Reporting a vulnerability

This plugin runs inside the micro editor and reads/writes files under `~/.config/micro/plug/bookmark/` (or `<cwd>/.bookmarks/` in `project` scope). The realistic threat surface is small but not zero — path-handling bugs and pattern injection could in principle let a crafted file or pattern misbehave.

If you find a vulnerability:

1. **Do not open a public issue.**
2. Email the maintainer via the address on the GitHub profile of [@haqk](https://github.com/haqk), or use GitHub's private vulnerability reporting on this repository.
3. Include a minimal reproducer (file contents, command sequence) and the plugin/micro versions.

You should expect an acknowledgement within 7 days. Fix timelines depend on severity and complexity; a coordinated disclosure window will be agreed before any public discussion.
