# Claude Code "Stop" hook, Windows version. Called by notify-discord.sh (the entry point).
# Posts a one-line summary to Discord when Claude finishes a reply.
#
# - Reads the webhook from the DISCORD_WEBHOOK environment variable. If the Claude app was started
#   before the variable was set, falls back to the User-level variable. Never hard-code it.
# - Compatible with Windows PowerShell 5.1. This file is ASCII only: 5.1 reads BOM-less scripts
#   as ANSI, so the emoji is built from its code point instead of written literally.
# - Always exits 0: a notification problem must never block Claude.

$ErrorActionPreference = 'Stop'

function Get-GitValue([string]$Dir, [string[]]$GitArgs) {
    # Native-command stderr + 'Stop' throws in PowerShell 5.1, so relax it just here.
    $ErrorActionPreference = 'SilentlyContinue'
    $out = & git -C $Dir @GitArgs 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) { return ("$out").Trim() }
    return ''
}

try {
    $webhook = $env:DISCORD_WEBHOOK
    if (-not $webhook) { $webhook = [Environment]::GetEnvironmentVariable('DISCORD_WEBHOOK', 'User') }
    if (-not $webhook) { exit 0 }

    # Read stdin as raw bytes and decode as UTF-8. ([Console]::In uses the OEM code page in 5.1,
    # which garbles accents and emoji.)
    $buffer = New-Object IO.MemoryStream
    [Console]::OpenStandardInput().CopyTo($buffer)
    $raw = [Text.Encoding]::UTF8.GetString($buffer.ToArray())

    # Unreadable input still produces a generic notification rather than none.
    $data = $null
    try { if ($raw.Trim()) { $data = $raw | ConvertFrom-Json } }
    catch { [Console]::Error.WriteLine("notify-discord: could not parse hook input: $($_.Exception.Message)") }
    if ($data -and $data.stop_hook_active) { exit 0 }

    # Summary = first non-empty line of Claude's last message, markdown stripped, max 180 chars.
    $summary = ''
    if ($data -and $data.last_assistant_message) {
        $lines = @($data.last_assistant_message -split "`r?`n" |
            ForEach-Object { (($_ -replace '^[#>\-\s]+', '') -replace '[*`]', '').Trim() } |
            Where-Object { $_ })
        if ($lines.Count -gt 0) { $summary = $lines[0] }
    }
    if (-not $summary) { $summary = 'finished a task' }
    if ($summary.Length -gt 180) { $summary = $summary.Substring(0, 177) + '...' }

    $dir = $null
    if ($data -and $data.cwd) { $dir = $data.cwd }
    elseif ($env:CLAUDE_PROJECT_DIR) { $dir = $env:CLAUDE_PROJECT_DIR }
    else { $dir = (Get-Location).Path }

    $branch = Get-GitValue $dir @('rev-parse', '--abbrev-ref', 'HEAD')
    if (-not $branch) { $branch = 'no-git' }
    $user = Get-GitValue $dir @('config', 'user.name')
    if (-not $user) { $user = $env:USERNAME }
    $top = Get-GitValue $dir @('rev-parse', '--show-toplevel')
    if (-not $top) { $top = $dir }
    $repo = Split-Path -Leaf $top

    $robot = [char]::ConvertFromUtf32(0x1F916)
    $content = "$robot $repo ($branch, $user): $summary"

    # allowed_mentions with an empty list stops @everyone / @here pings.
    $body = @{ content = $content; allowed_mentions = @{ parse = @() } } | ConvertTo-Json -Compress -Depth 3

    if ($env:NOTIFY_DISCORD_DRY_RUN -eq '1') {
        # Testing aid: print the payload instead of posting it. Write UTF-8 bytes so emoji survive.
        $bytes = [Text.Encoding]::UTF8.GetBytes("DRY RUN payload: $body`n")
        [Console]::OpenStandardOutput().Write($bytes, 0, $bytes.Length)
        exit 0
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Uri $webhook -Method Post -ContentType 'application/json; charset=utf-8' `
        -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 8 | Out-Null
}
catch {
    # Short note for debugging; never print the webhook itself.
    [Console]::Error.WriteLine("notify-discord: $($_.Exception.Message)")
}
exit 0
