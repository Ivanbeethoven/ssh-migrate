#Requires -Version 5.1
<#
.SYNOPSIS
    Make a fresh server feel like home: copy your GitHub CLI (gh) and git
    configuration over SSH, and install your SSH public key.

.DESCRIPTION
    Windows / PowerShell port of ssh-migrate. By default it migrates everything
    to the target host:
      * your SSH public key  -> remote ~/.ssh/authorized_keys
      * gh config            -> remote ~/.config/gh (hosts.yml, config.yml)
      * git config           -> remote ~/.config/git/config and ~/.gitconfig
    If the gh token is kept in the OS keyring instead of hosts.yml, it is
    fetched locally with `gh auth token` and re-applied on the remote through
    `gh auth login --with-token`. Existing remote files are backed up first.

.PARAMETER Target
    Destination host, e.g. user@example.com, or a Host alias from ~/.ssh/config.

.PARAMETER DryRun
    Show what would happen without changing anything.

.PARAMETER Port
    SSH port.

.PARAMETER Identity
    SSH private key file; its .pub is installed as well.

.PARAMETER NoKey
    Skip installing the SSH public key.

.PARAMETER NoGh
    Skip the gh configuration.

.PARAMETER NoGit
    Skip the git configuration.

.PARAMETER Credentials
    Also copy ~/.git-credentials (plaintext secrets).

.PARAMETER Pubkey
    Public key file(s) to install. Repeatable.

.EXAMPLE
    .\ssh-migrate.ps1 myserver

.EXAMPLE
    .\ssh-migrate.ps1 -DryRun root@203.0.113.10
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Target,

    [switch]$DryRun,
    [int]$Port,
    [string]$Identity,
    [switch]$NoKey,
    [switch]$NoGh,
    [switch]$NoGit,
    [switch]$Credentials,
    [string[]]$Pubkey
)

$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Write-Info { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Warn { param([string]$Message) Write-Host "warning: $Message" -ForegroundColor Yellow }
function Die { param([string]$Message) Write-Host "ssh-migrate: $Message" -ForegroundColor Red; exit 1 }

if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { Die 'ssh not found' }

# --- ssh options ------------------------------------------------------------
$sshCommon = @('-o', 'ConnectTimeout=10')
if ($Port) { $sshCommon += @('-p', "$Port") }
if ($Identity) { $sshCommon += @('-i', $Identity) }

function New-B64 { param([string]$Text) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text)) }
function ConvertTo-Lf { param([string]$Text) (($Text -replace "`r`n", "`n") -replace "`r", "") }

# Run a bash script on the remote. The script is base64-encoded so line endings
# and quoting never get mangled by PowerShell's native-command pipeline.
function Invoke-Remote {
    param(
        [string]$Script,
        [string[]]$ScriptArgs = @(),
        [switch]$PassThru
    )
    $b64 = New-B64 (ConvertTo-Lf $Script)
    $argLine = ($ScriptArgs -join ' ')
    $cmd = "echo $b64 | base64 -d | bash -s -- $argLine"
    $sshArgs = $sshCommon + @('--', $Target, $cmd)
    if ($PassThru) {
        $out = & ssh @sshArgs
        if ($LASTEXITCODE -ne 0) { throw "remote command failed (exit $LASTEXITCODE)" }
        return $out
    }
    & ssh @sshArgs
    if ($LASTEXITCODE -ne 0) { throw "remote command failed (exit $LASTEXITCODE)" }
}

# --- locate local config ----------------------------------------------------
function Get-GhConfigDir {
    if ($env:GH_CONFIG_DIR) { return $env:GH_CONFIG_DIR }
    if ($env:APPDATA) { return (Join-Path $env:APPDATA 'GitHub CLI') }
    return (Join-Path $HOME '.config/gh')
}

$ghDir = Get-GhConfigDir
$ghFiles = @()
foreach ($name in @('hosts.yml', 'config.yml')) {
    $local = Join-Path $ghDir $name
    if (Test-Path -LiteralPath $local) {
        $ghFiles += [pscustomobject]@{ Local = $local; Remote = ".config/gh/$name" }
    }
}
$doGh = (-not $NoGh) -and ($ghFiles.Count -gt 0)
if (-not $NoGh -and $ghFiles.Count -eq 0) {
    Write-Warn "no gh config at '$ghDir'; run 'gh auth login' first (skipping gh)"
}

$gitFiles = @()
if (-not $NoGit) {
    $xdg = Join-Path $HOME '.config/git/config'
    if (Test-Path -LiteralPath $xdg) {
        $gitFiles += [pscustomobject]@{ Local = $xdg; Remote = '.config/git/config' }
    }
    $gitCandidates = @(Join-Path $HOME '.gitconfig')
    if ($env:USERPROFILE) { $gitCandidates += (Join-Path $env:USERPROFILE '.gitconfig') }
    foreach ($cand in $gitCandidates) {
        if ((Test-Path -LiteralPath $cand) -and -not ($gitFiles | Where-Object { $_.Remote -eq '.gitconfig' })) {
            $gitFiles += [pscustomobject]@{ Local = $cand; Remote = '.gitconfig' }
        }
    }
    if ($Credentials) {
        $creds = Join-Path $HOME '.git-credentials'
        if (Test-Path -LiteralPath $creds) {
            $gitFiles += [pscustomobject]@{ Local = $creds; Remote = '.git-credentials' }
        }
    }
}

$files = @($ghFiles) + @($gitFiles)

# --- resolve public keys ----------------------------------------------------
$copyKey = -not $NoKey
$pubkeys = @()
if ($copyKey) {
    if ($Pubkey -and $Pubkey.Count -gt 0) {
        $pubkeys += $Pubkey
    }
    else {
        if ($Identity -and (Test-Path -LiteralPath "$Identity.pub")) { $pubkeys += "$Identity.pub" }
        foreach ($k in @("$HOME/.ssh/id_ed25519.pub", "$HOME/.ssh/id_rsa.pub", "$HOME/.ssh/id_ecdsa.pub")) {
            if (Test-Path -LiteralPath $k) { $pubkeys += $k }
        }
    }
    if ($pubkeys.Count -eq 0) {
        Write-Warn 'no SSH public key found (id_ed25519.pub, id_rsa.pub, id_ecdsa.pub); skipping key install'
        $copyKey = $false
    }
}

if ($files.Count -eq 0 -and -not $copyKey) { Die 'nothing to migrate' }
if ($files.Count -gt 0) { Write-Info ('Will copy: ' + (($files | ForEach-Object { $_.Remote }) -join ' ')) }
if ($copyKey) { Write-Info ('Will install public key(s): ' + ($pubkeys -join ', ')) }

# --- connect ----------------------------------------------------------------
try {
    $resolved = & ssh @($sshCommon + @('-G', '--', $Target)) 2>$null
    if ($LASTEXITCODE -eq 0 -and $resolved) {
        $rHost = ($resolved | Where-Object { $_ -match '^\s*hostname\s' } | Select-Object -First 1) -replace '^\s*hostname\s+', ''
        $rUser = ($resolved | Where-Object { $_ -match '^\s*user\s' } | Select-Object -First 1) -replace '^\s*user\s+', ''
        $rPort = ($resolved | Where-Object { $_ -match '^\s*port\s' } | Select-Object -First 1) -replace '^\s*port\s+', ''
        Write-Info "SSH target '$Target' -> $rUser@$rHost`:$rPort"
    }
}
catch { }

Write-Info "Connecting to $Target ..."
try {
    $remoteHome = (Invoke-Remote -Script 'printf %s "$HOME"' -PassThru | Out-String).Trim()
}
catch { Die "cannot ssh to $Target" }
if (-not $remoteHome) { Die 'remote HOME is empty' }
Write-Info "Remote HOME: $remoteHome"

if ($DryRun) { Write-Info "dry-run: stopping before touching $Target"; exit 0 }

# --- transfer ---------------------------------------------------------------
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$writeScript = @'
set -e
home="$1"; rel="$2"; b64="$3"; ts="$4"
dst="$home/$rel"
mkdir -p "$(dirname "$dst")"
if [ -e "$dst" ]; then cp -a "$dst" "$dst.bak-$ts"; echo "backed up"; fi
printf '%s' "$b64" | base64 -d > "$dst"
case "$rel" in
    .config/gh/*|.gitconfig|.git-credentials) chmod 600 "$dst" ;;
esac
'@

foreach ($file in $files) {
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.Local))
    $r = Invoke-Remote -Script $writeScript -ScriptArgs @($remoteHome, $file.Remote, $b64, $ts) -PassThru
    Write-Info "  $($file.Remote): $r"
}
if ($doGh) {
    Invoke-Remote -Script 'home="$1"; if [ -d "$home/.config/gh" ]; then chmod 700 "$home/.config/gh"; fi' -ScriptArgs @($remoteHome)
}

# --- keyring token fallback -------------------------------------------------
if ($doGh) {
    $hostsFile = $ghFiles | Where-Object { $_.Remote -eq '.config/gh/hosts.yml' } | Select-Object -First 1
    if ($hostsFile) {
        $content = Get-Content -Raw -LiteralPath $hostsFile.Local
        $hosts = @()
        $hasToken = @{}
        $current = $null
        foreach ($line in ($content -split "`n")) {
            if ($line -match '^([^\s].*):\s*$') {
                $current = $Matches[1].Trim()
                $hosts += $current
                $hasToken[$current] = $false
            }
            elseif ($current -and $line -match '^\s+oauth_token:\s*\S') {
                $hasToken[$current] = $true
            }
        }
        $missing = @($hosts | Where-Object { -not $hasToken[$_] })
        if ($missing.Count -gt 0) {
            $remoteHasGh = ((Invoke-Remote -Script 'if command -v gh >/dev/null 2>&1; then echo yes; else echo no; fi' -PassThru | Out-String).Trim() -eq 'yes')
            if (-not $remoteHasGh) {
                Write-Warn "remote has no 'gh' binary; cannot inject keyring token for: $($missing -join ', ')"
            }
            elseif (Get-Command gh -ErrorAction SilentlyContinue) {
                foreach ($h in $missing) {
                    $token = (& gh auth token --hostname $h 2>$null)
                    if ($LASTEXITCODE -eq 0 -and $token) {
                        Write-Info "Injecting keyring token for $h on remote ..."
                        $sshArgs = $sshCommon + @('--', $Target, "gh auth login --hostname $h --with-token")
                        $token.Trim() | & ssh @sshArgs
                        if ($LASTEXITCODE -ne 0) { Write-Warn "failed to inject token for $h" }
                    }
                    else {
                        Write-Warn "no local token available for $h"
                    }
                }
            }
        }
    }
}

# --- verify -----------------------------------------------------------------
if ($doGh) {
    Write-Info "Verifying gh auth on $Target ..."
    try {
        Invoke-Remote -Script 'command -v gh >/dev/null 2>&1 && gh auth status' | Out-Null
        Write-Info 'gh is authenticated on the remote.'
    }
    catch {
        Write-Warn 'gh auth not confirmed on remote (gh may be missing or token not copied).'
    }
}

# --- install SSH public key(s) ---------------------------------------------
if ($copyKey) {
    Write-Info "Installing SSH public key(s) on $Target ..."
    $keyScript = @'
set -e
home="$1"; kb64="$2"
key="$(printf '%s' "$kb64" | base64 -d 2>/dev/null || printf '%s' "$kb64" | base64 -D)"
dir="$home/.ssh"; ak="$dir/authorized_keys"
mkdir -p "$dir"; chmod 700 "$dir"
touch "$ak"; chmod 600 "$ak"
if grep -qF -- "$key" "$ak"; then
    echo "already present"
else
    cp -a "$ak" "$ak.bak-$(date +%Y%m%d-%H%M%S)"
    printf '%s\n' "$key" >> "$ak"
    echo "added"
fi
'@
    foreach ($pub in $pubkeys) {
        if (-not (Test-Path -LiteralPath $pub)) { Write-Warn "public key not found: $pub"; continue }
        $key = (Get-Content -Raw -LiteralPath $pub).Trim()
        if (-not $key) { Write-Warn "empty public key: $pub"; continue }
        try {
            $r = Invoke-Remote -Script $keyScript -ScriptArgs @($remoteHome, (New-B64 $key)) -PassThru
            Write-Info "  $pub -> $r"
        }
        catch { Write-Warn "failed to install $pub" }
    }
}

Write-Info "Done. Copied to ${Target}:$remoteHome"
