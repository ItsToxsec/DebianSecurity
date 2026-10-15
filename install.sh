#!/usr/bin/env bash
set -Eeuo pipefail
# Install Debian Testing equivalents of the NixSecurity tool lists.
# Run as regular user with sudo privileges; never mixes Kali repositories.
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPORT="${REPORT_DIR:-$PWD/nixsecurity-install-report-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$REPORT"
if [[ ${EUID} -eq 0 ]]; then echo 'Run as a regular sudo-enabled user, not root.' >&2; exit 1; fi
if [[ ! -r /etc/os-release ]]; then echo 'Cannot identify OS.' >&2; exit 1; fi
. /etc/os-release
if [[ ${ID:-} != debian ]]; then echo "Expected Debian, got ${ID:-unknown}" >&2; exit 1; fi
command -v sudo >/dev/null || { echo 'sudo is required' >&2; exit 1; }
command -v apt-cache >/dev/null || { echo 'APT is required' >&2; exit 1; }
usage(){ cat <<'HELP'
Usage: ./install.sh [--all | --categories base,offense,defence,malware] [--dry-run] [--no-vscode] [--no-docker]
Default: all categories, VS Code and Docker. APT-only: unavailable packages are logged, not silently replaced by untrusted sources.
HELP
}
CATEGORIES='base,offense,defence,malware'; DRY=0; VSCODE=1; DOCKER=1
while (($#)); do
 case "$1" in
  --all) CATEGORIES='base,offense,defence,malware';;
  --categories) [[ $# -ge 2 ]] || { usage; exit 2; }; CATEGORIES="$2"; shift;;
  --dry-run) DRY=1;;
  --no-vscode) VSCODE=0;;
  --no-docker) DOCKER=0;;
  -h|--help) usage; exit 0;;
  *) echo "Unknown argument: $1" >&2; usage; exit 2;;
 esac
 shift
done
IFS=',' read -ra SELECTED <<< "$CATEGORIES"
for cat in "${SELECTED[@]}"; do
 case "$cat" in base|offense|defence|malware) ;; *) echo "Invalid category: $cat" >&2; exit 2;; esac
 [[ -f "$ROOT/$cat.txt" ]] || { echo "Missing $ROOT/$cat.txt" >&2; exit 1; }
done
# Debian package names, including alternative candidates where names differ.
declare -A MAP=(
 [_7zz]='7zip p7zip-full' [fd]='fd-find' [bind]='bind9-dnsutils bind9-utils' [dnsutils]='bind9-dnsutils dnsutils'
 [inetutils]='inetutils-ping inetutils-tools' [netcat-openbsd]='netcat-openbsd' [iproute2]='iproute2'
 [python3]='python3' [tshark]='tshark' [wireshark]='wireshark' [wireshark-cli]='tshark'
 [rustscan]='rustscan' [amass]='amass' [subfinder]='subfinder' [dnsenum]='dnsenum'
 [feroxbuster]='feroxbuster' [gobuster]='gobuster' [ffuf]='ffuf'
 [metasploit]='metasploit-framework' [exploitdb]='exploitdb' [enum4linux-ng]='enum4linux-ng'
 [impacket]='python3-impacket impacket-scripts' [netexec]='netexec' [testssl.sh]='testssl.sh testssl'
 [whatweb]='whatweb' [osquery]='osquery' [audit]='auditd' [autopsy]='autopsy'
 [exiftool]='libimage-exiftool-perl' [hashdeep]='hashdeep' [clamtk]='clamtk'
 [trivy]='trivy' [grype]='grype' [syft]='syft' [ghidra]='ghidra'
 [pwndbg]='python3-pwndbg pwndbg' [imhex]='imhex' [hexyl]='hexyl'
 [checksec]='checksec' [upx]='upx-ucl upx' [rizin]='rizin' [cutter]='cutter'
 [binwalk]='binwalk' [smbmap]='smbmap' [patchelf]='patchelf'
)
: > "$REPORT/requested.tsv"; : > "$REPORT/unavailable.tsv"; : > "$REPORT/available.txt"
declare -A seen=()
for cat in "${SELECTED[@]}"; do
 while IFS= read -r nix || [[ -n "$nix" ]]; do
  [[ -z "$nix" || "$nix" == \#* ]] && continue
  [[ "$nix" =~ ^[a-zA-Z0-9_.+-]+$ ]] || { printf '%s\t%s\tinvalid name\n' "$cat" "$nix" >> "$REPORT/unavailable.tsv"; continue; }
  printf '%s\t%s\n' "$cat" "$nix" >> "$REPORT/requested.tsv"
 done < "$ROOT/$cat.txt"
done
if ((DRY == 0)); then
 sudo -v
 sudo apt-get update
fi
while IFS=$'\t' read -r cat nix; do
 candidates="${MAP[$nix]:-$nix}"
 found=''
 for candidate in $candidates; do
  # Candidate must exist in currently configured APT sources.
  if apt-cache policy "$candidate" | grep -Eq '^[[:space:]]+Candidate: [^ (]+' && ! apt-cache policy "$candidate" | grep -q 'Candidate: (none)'; then
   found="$candidate"; break
  fi
 done
 if [[ -n "$found" ]]; then
  if [[ -z "${seen[$found]+x}" ]]; then printf '%s\n' "$found" >> "$REPORT/available.txt"; seen[$found]=1; fi
 else
  printf '%s\t%s\t%s\n' "$cat" "$nix" "$candidates" >> "$REPORT/unavailable.tsv"
 fi
done < "$REPORT/requested.tsv"
# SPICE and Proxmox QEMU guest agent; these are VM integrations, not security tools.
for pkg in spice-vdagent qemu-guest-agent; do
 if apt-cache policy "$pkg" | grep -qE 'Candidate: [^ (]+' && ! apt-cache policy "$pkg" | grep -q 'Candidate: (none)'; then
  [[ -n "${seen[$pkg]+x}" ]] || { echo "$pkg" >> "$REPORT/available.txt"; seen[$pkg]=1; }
 else echo "vm-integration $pkg" >> "$REPORT/unavailable.tsv"; fi
done
sort -u -o "$REPORT/available.txt" "$REPORT/available.txt"
echo "Packages available: $(wc -l < "$REPORT/available.txt")"
echo "Unmapped/unavailable entries: $(wc -l < "$REPORT/unavailable.tsv")"
if ((DRY)); then
 echo 'DRY RUN: no packages installed, no repositories modified.'
 echo "Report: $REPORT"
 exit 0
fi
# Install packages individually so one broken/unavailable package does not stop the remainder.
: > "$REPORT/failed-installs.txt"
while IFS= read -r pkg; do
 echo "Installing $pkg ..."
 if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"; then
  echo "$pkg" >> "$REPORT/failed-installs.txt"
 fi
done < "$REPORT/available.txt"
if ((DOCKER)); then
 # Debian's own Docker package, no external Docker repository.
 if apt-cache policy docker.io | grep -qE 'Candidate: [^ (]+' && ! apt-cache policy docker.io | grep -q 'Candidate: (none)'; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io || echo docker.io >> "$REPORT/failed-installs.txt"
  sudo systemctl enable --now docker.service || true
 else echo docker.io >> "$REPORT/unavailable.tsv"; fi
fi
if ((VSCODE)); then
 # Microsoft's official VS Code repository; check download success before modifying sources.
 sudo apt-get install -y ca-certificates curl gpg
 tmpkey="$(mktemp)"; trap 'rm -f "$tmpkey"' EXIT
 if curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > "$tmpkey"; then
  sudo install -Dm644 "$tmpkey" /etc/apt/keyrings/packages.microsoft.gpg
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main\n' "$(dpkg --print-architecture)" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y code || echo code >> "$REPORT/failed-installs.txt"
 else echo 'VS Code signing key download failed; repository not added.' >&2; echo code >> "$REPORT/failed-installs.txt"; fi
fi
sudo systemctl enable --now qemu-guest-agent.service 2>/dev/null || true
# Do not automatically add user to docker group: it grants root-equivalent privileges.
echo "Done. Report: $REPORT"
echo 'Review unavailable.tsv and failed-installs.txt. Re-login after installation.'
