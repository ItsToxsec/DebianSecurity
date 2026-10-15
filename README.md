# NixSecurity -> Debian Testing

Source: the four package lists in the standalone NixOS Kali-replacement configuration supplied earlier in this conversation. These are not guaranteed to match the latest GitHub NixSecurity branch.

Run on a **Debian Testing** VM as a regular user with sudo privileges:

```bash
./install.sh --dry-run
./install.sh --all
# Or select categories:
./install.sh --categories base,defence,malware
```

Default also installs `spice-vdagent`, `qemu-guest-agent`, Debian's `docker.io`, and Microsoft VS Code `code` from the official Microsoft apt repository. Use `--no-vscode` or `--no-docker` to omit either.

APT-only mapping: tools not packaged in your configured Debian repositories are listed in `unavailable.tsv`. Some Kali-specific tools (e.g. Metasploit) may be unavailable; this installer deliberately does not add Kali repositories or automatically run untrusted install scripts. `failed-installs.txt` lists packages that APT found but could not install. Reports are stored in the current directory by default; override with `REPORT_DIR=/path`.

For Wireshark packet capture without root, run `sudo dpkg-reconfigure wireshark-common` and add your user to the `wireshark` group, then log out and back in. Docker group membership is deliberately not granted because it is root-equivalent. SPICE display/clipboard features require a compatible SPICE client.

A full desktop environment and configuration are not installed by this script; it focuses on the NixSecurity application lists and the requested VM integrations.
