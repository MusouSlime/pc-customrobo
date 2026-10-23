# Custom Robo launcher for Windows.
#
# A thin WinForms front end over launcher/core.py: it builds the port from the
# user's own disc image with the compiler and SDL3 already on this PC.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:CorePath = Join-Path $script:Root "launcher\core.py"
$script:ProjectRoot = Join-Path $script:Root "project"
if (-not (Test-Path (Join-Path $script:ProjectRoot "wiikit"))) {
    $script:ProjectRoot = $script:Root
}

$script:SettingsDir = Join-Path $env:APPDATA "CustomRoboLauncher"
$script:SettingsFile = Join-Path $script:SettingsDir "settings.json"
$script:Settings = $null
if (Test-Path $script:SettingsFile) {
    try { $script:Settings = Get-Content -Raw $script:SettingsFile | ConvertFrom-Json } catch { }
}
if (-not $script:Settings) { $script:Settings = [pscustomobject]@{} }

function Get-Setting([string]$Name, [string]$Default) {
    $p = $script:Settings.PSObject.Properties[$Name]
    if ($p -and $p.Value) { return [string]$p.Value }
    return $Default
}

function Save-Settings {
    New-Item -ItemType Directory -Force -Path $script:SettingsDir | Out-Null
    $obj = [pscustomobject]@{
        iso    = $script:txtIso.Text
        work   = $script:txtWork.Text
        fonts  = $script:txtFonts.Text
        sdl3   = $script:txtSdl3.Text
        unlock = if ($script:chkUnlock.Checked) { "1" } else { "0" }
    }
    $obj | ConvertTo-Json | Set-Content -Encoding UTF8 $script:SettingsFile
}

function Test-Python([string]$Exe, [string[]]$Prefix) {
    $a = @()
    if ($Prefix) { $a += $Prefix }
    $a += @("-c", "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)")
    try {
        & $Exe @a 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Find-Python {
    # The package ships an embeddable Python, so a clean PC needs no install.
    $bundled = Join-Path $script:Root "deps\python\python.exe"
    if ((Test-Path -LiteralPath $bundled) -and (Test-Python $bundled @())) {
        return [pscustomobject]@{ Exe = $bundled; Prefix = @() }
    }
    # The py launcher is the most reliable on Windows; python.exe can be the
    # Microsoft Store alias, which opens the Store instead of running Python.
    $p = Get-Command py -ErrorAction SilentlyContinue
    if ($p) {
        $exe = $p.Path
        if (-not $exe) { $exe = $p.Source }
        if ($exe -and (Test-Python $exe @("-3"))) {
            return [pscustomobject]@{ Exe = $exe; Prefix = @("-3") }
        }
    }
    foreach ($name in @("python", "python3")) {
        $p = Get-Command $name -ErrorAction SilentlyContinue
        if ($p) {
            $exe = $p.Path
            if (-not $exe) { $exe = $p.Source }
            if ($exe -and (Test-Python $exe @())) {
                return [pscustomobject]@{ Exe = $exe; Prefix = @() }
            }
        }
    }
    $local = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python313\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"),
        "C:\Python313\python.exe",
        "C:\Python312\python.exe",
        "C:\Python311\python.exe"
    )
    foreach ($exe in $local) {
        if ($exe -and (Test-Path -LiteralPath $exe) -and (Test-Python $exe @())) {
            return [pscustomobject]@{ Exe = $exe; Prefix = @() }
        }
    }
    return $null
}

function Install-Python {
    $existing = Find-Python
    if ($existing) {
        [System.Windows.Forms.MessageBox]::Show(
            "Python is already installed:`r`n$($existing.Exe)",
            "Custom Robo") | Out-Null
        return
    }

    $script:lblStatus.Text = "Installing Python 3.12..."
    $installed = $false

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        try {
            $wgArgs = @("install", "--id", "Python.Python.3.12", "-e",
                        "--source", "winget", "--accept-package-agreements",
                        "--accept-source-agreements", "--silent")
            $p = Start-Process -FilePath $winget.Source -ArgumentList $wgArgs `
                -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -eq 0 -and (Find-Python)) { $installed = $true }
        } catch { }
    }

    if (-not $installed) {
        try {
            $url = "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe"
            $out = Join-Path $env:TEMP "python-3.12.10-amd64.exe"
            $script:lblStatus.Text = "Downloading Python 3.12..."
            Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
            $script:lblStatus.Text = "Installing Python 3.12..."
            $p = Start-Process -FilePath $out -Wait -PassThru -ArgumentList `
                "/passive InstallAllUsers=0 PrependPath=1 Include_launcher=1 Include_test=0"
            if ($p.ExitCode -eq 0 -and (Find-Python)) { $installed = $true }
        } catch { }
    }

    $py = Find-Python
    if ($py) {
        $script:lblStatus.Text = "Python installed. Press Build."
        [System.Windows.Forms.MessageBox]::Show(
            "Python is ready:`r`n$($py.Exe)`r`n`r`nPress Build to continue.",
            "Custom Robo") | Out-Null
    } else {
        $script:lblStatus.Text = "Python install did not finish."
        [System.Windows.Forms.MessageBox]::Show(
            "Python could not be installed automatically.`r`n`r`n" +
            "Install Python 3.10 or newer from python.org, tick `"Add Python to PATH`", " +
            "then restart the launcher.",
            "Custom Robo") | Out-Null
    }
}

function Ensure-Python {
    $py = Find-Python
    if ($py) { return $py }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "Python 3.10 or newer is required to build and run the game.`r`n`r`n" +
        "Install it now?",
        "Custom Robo", [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        Install-Python
        return (Find-Python)
    }
    return $null
}

function Format-Arg([string]$Value) {
    if ($Value -match '[\s"]') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }
    return $Value
}

function Show-Log-Tail([string]$Path, [int]$Lines = 22) {
    if (Test-Path $Path) {
        return (Get-Content $Path -Tail $Lines -ErrorAction SilentlyContinue | Out-String)
    }
    return ""
}

# ---------------------------------------------------------------------------
# the window

$form = New-Object System.Windows.Forms.Form
$form.Text = "Custom Robo: Battle Revolution"
$form.ClientSize = New-Object System.Drawing.Size(820, 640)
$form.MinimumSize = New-Object System.Drawing.Size(700, 520)
$form.StartPosition = "CenterScreen"

function Add-Label([string]$Text, [int]$X, [int]$Y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size(95, 22)
    $form.Controls.Add($l)
}

function Add-TextBox([string]$Text, [int]$X, [int]$Y, [int]$W) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Text = $Text
    $t.Location = New-Object System.Drawing.Point($X, $Y)
    $t.Size = New-Object System.Drawing.Size($W, 24)
    $t.Anchor = "Top,Left,Right"
    $form.Controls.Add($t)
    return $t
}

function Add-Browse([int]$X, [int]$Y, $Handler) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = "Browse..."
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size(88, 25)
    $b.Anchor = "Top,Right"
    $b.Add_Click($Handler)
    $form.Controls.Add($b)
    return $b
}

Add-Label "Disc image" 12 16
$script:txtIso = Add-TextBox (Get-Setting "iso" "") 112 12 590
Add-Browse 710 11 { Browse-Iso } | Out-Null

Add-Label "Working folder" 12 56
$script:txtWork = Add-TextBox (Get-Setting "work" (Join-Path $env:LOCALAPPDATA "CustomRoboLauncher")) 112 52 590
Add-Browse 710 51 { Browse-Work } | Out-Null

Add-Label "Dolphin fonts" 12 96
$script:txtFonts = Add-TextBox (Get-Setting "fonts" "") 112 92 590
Add-Browse 710 91 { Browse-Fonts } | Out-Null

Add-Label "SDL3 folder" 12 136
$script:txtSdl3 = Add-TextBox (Get-Setting "sdl3" "") 112 132 590
Add-Browse 710 131 { Browse-Sdl3 } | Out-Null

$btnBuild = New-Object System.Windows.Forms.Button
$btnBuild.Text = "Build"
$btnBuild.Location = New-Object System.Drawing.Point(112, 172)
$btnBuild.Size = New-Object System.Drawing.Size(100, 30)
$btnBuild.Add_Click({ Start-Build })
$form.Controls.Add($btnBuild)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run"
$btnRun.Location = New-Object System.Drawing.Point(222, 172)
$btnRun.Size = New-Object System.Drawing.Size(100, 30)
$btnRun.Add_Click({ Start-Game })
$form.Controls.Add($btnRun)

$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Text = "Open folder"
$btnOpen.Location = New-Object System.Drawing.Point(332, 172)
$btnOpen.Size = New-Object System.Drawing.Size(110, 30)
$btnOpen.Add_Click({
    $w = $script:txtWork.Text
    New-Item -ItemType Directory -Force -Path $w | Out-Null
    Start-Process explorer.exe $w
})
$form.Controls.Add($btnOpen)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel build"
$btnCancel.Location = New-Object System.Drawing.Point(452, 172)
$btnCancel.Size = New-Object System.Drawing.Size(110, 30)
$btnCancel.Enabled = $false
$btnCancel.Add_Click({ Cancel-Build })
$form.Controls.Add($btnCancel)

$btnPython = New-Object System.Windows.Forms.Button
$btnPython.Text = "Install Python"
$btnPython.Location = New-Object System.Drawing.Point(572, 172)
$btnPython.Size = New-Object System.Drawing.Size(120, 30)
$btnPython.Add_Click({ Install-Python })
$form.Controls.Add($btnPython)

$btnDiag = New-Object System.Windows.Forms.Button
$btnDiag.Text = "Diagnose"
$btnDiag.Location = New-Object System.Drawing.Point(702, 172)
$btnDiag.Size = New-Object System.Drawing.Size(100, 30)
$btnDiag.Add_Click({ Start-Diagnose })
$form.Controls.Add($btnDiag)

$script:chkUnlock = New-Object System.Windows.Forms.CheckBox
$script:chkUnlock.Text = "Unlock all robos, parts and stages"
$script:chkUnlock.Location = New-Object System.Drawing.Point(112, 208)
$script:chkUnlock.Size = New-Object System.Drawing.Size(320, 24)
$script:chkUnlock.Checked = -not (@("0", "false", "False") -contains (Get-Setting "unlock" "1"))
$script:chkUnlock.Add_CheckedChanged({ Save-Settings })
$form.Controls.Add($script:chkUnlock)

$script:chkWhite = New-Object System.Windows.Forms.CheckBox
$script:chkWhite.Text = "Force white shaders (diagnose)"
$script:chkWhite.Location = New-Object System.Drawing.Point(450, 208)
$script:chkWhite.Size = New-Object System.Drawing.Size(340, 24)
$form.Controls.Add($script:chkWhite)

$script:progress = New-Object System.Windows.Forms.ProgressBar
$script:progress.Location = New-Object System.Drawing.Point(112, 240)
$script:progress.Size = New-Object System.Drawing.Size(686, 16)
$script:progress.Anchor = "Top,Left,Right"
$form.Controls.Add($script:progress)

$script:lblStatus = New-Object System.Windows.Forms.Label
$script:lblStatus.Text = "Choose your disc image, then press Build."
$script:lblStatus.Location = New-Object System.Drawing.Point(112, 260)
$script:lblStatus.Size = New-Object System.Drawing.Size(686, 22)
$script:lblStatus.Anchor = "Top,Left,Right"
$form.Controls.Add($script:lblStatus)
if (-not (Find-Python)) {
    $script:lblStatus.Text = "Python 3 is not installed. Press Install Python."
}

$script:txtLog = New-Object System.Windows.Forms.TextBox
$script:txtLog.Multiline = $true
$script:txtLog.ReadOnly = $true
$script:txtLog.ScrollBars = "Both"
$script:txtLog.WordWrap = $false
$script:txtLog.Font = New-Object System.Drawing.Font("Consolas", 8.5)
$script:txtLog.Location = New-Object System.Drawing.Point(12, 290)
$script:txtLog.Size = New-Object System.Drawing.Size(796, 334)
$script:txtLog.Anchor = "Top,Bottom,Left,Right"
$form.Controls.Add($script:txtLog)

$script:Timer = New-Object System.Windows.Forms.Timer
$script:Timer.Interval = 500
$script:Timer.Add_Tick({ Refresh-Build })
$script:DiagProc = $null
$script:DiagTimer = New-Object System.Windows.Forms.Timer
$script:DiagTimer.Interval = 500
$script:DiagTimer.Add_Tick({ Check-Diagnose })
$script:Proc = $null
$script:Building = $false

# ---------------------------------------------------------------------------
# actions

function Browse-Iso {
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Title = "Choose your Custom Robo (USA) disc image"
    $d.Filter = "Disc images (*.iso;*.rvz;*.wia;*.gcm;*.wbfs)|*.iso;*.rvz;*.wia;*.gcm;*.wbfs|All files (*.*)|*.*"
    if ($script:txtIso.Text) { $d.InitialDirectory = Split-Path $script:txtIso.Text -Parent }
    if ($d.ShowDialog() -eq "OK") {
        $script:txtIso.Text = $d.FileName
        Save-Settings
    }
}

function Browse-Work {
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = "Folder for the extracted disc, recompiled sources and build"
    if ($d.ShowDialog() -eq "OK") {
        $script:txtWork.Text = $d.SelectedPath
        Save-Settings
    }
}

function Browse-Fonts {
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = "Dolphin's Sys\GC folder (contains font_western.bin)"
    if ($d.ShowDialog() -eq "OK") {
        $script:txtFonts.Text = $d.SelectedPath
        Save-Settings
    }
}

function Browse-Sdl3 {
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = "SDL3 development package (the folder containing cmake\SDL3 or lib\cmake\SDL3)"
    if ($d.ShowDialog() -eq "OK") {
        $script:txtSdl3.Text = $d.SelectedPath
        Save-Settings
    }
}

function Set-Busy([bool]$Busy) {
    $script:Building = $Busy
    $btnBuild.Enabled = -not $Busy
    $btnRun.Enabled = -not $Busy
    $btnOpen.Enabled = -not $Busy
    $btnCancel.Enabled = $Busy
    if ($Busy) {
        $script:progress.Style = "Marquee"
        $script:progress.MarqueeAnimationSpeed = 30
    } else {
        $script:progress.Style = "Blocks"
        $script:progress.Value = 0
    }
}

function Start-Build {
    if ($script:Building) { return }
    $iso = $script:txtIso.Text.Trim()
    $work = $script:txtWork.Text.Trim()
    if (-not (Test-Path -LiteralPath $iso -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show("Choose your disc image first.", "Custom Robo") | Out-Null
        return
    }
    if (-not $work) {
        [System.Windows.Forms.MessageBox]::Show("Choose a working folder first.", "Custom Robo") | Out-Null
        return
    }
    if (-not (Test-Path $script:CorePath)) {
        [System.Windows.Forms.MessageBox]::Show("launcher\core.py is missing from this package.", "Custom Robo") | Out-Null
        return
    }
    $py = Ensure-Python
    if (-not $py) { return }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Save-Settings

    $env:CUSTOM_ROBO_BUNDLE = $script:Root
    $env:CUSTOM_ROBO_PROJECT = $script:ProjectRoot
    $env:PYTHONPATH = $script:ProjectRoot

    $script:LogPath = Join-Path $work "build.log"
    $script:StdoutPath = Join-Path $work "launcher-stdout.txt"
    $script:StderrPath = Join-Path $work "launcher-stderr.txt"
    Remove-Item -Force -ErrorAction SilentlyContinue $script:StdoutPath, $script:StderrPath

    $argv = @()
    $argv += $py.Prefix
    $argv += @($script:CorePath, "build", "--iso", $iso, "--work", $work, "--log", $script:LogPath)
    if ($script:txtSdl3.Text.Trim()) { $argv += @("--sdl3", $script:txtSdl3.Text.Trim()) }
    if ($script:txtFonts.Text.Trim()) { $argv += @("--fonts", $script:txtFonts.Text.Trim()) }
    $argLine = (($argv | ForEach-Object { Format-Arg $_ }) -join " ")

    $script:txtLog.Text = "Building...`r`n"
    $script:lblStatus.Text = "Starting the build..."
    Set-Busy $true
    try {
        $script:Proc = Start-Process -FilePath $py.Exe -ArgumentList $argLine `
            -WorkingDirectory $script:Root -RedirectStandardOutput $script:StdoutPath `
            -RedirectStandardError $script:StderrPath -NoNewWindow -PassThru
        $script:Timer.Start()
    } catch {
        Set-Busy $false
        [System.Windows.Forms.MessageBox]::Show("Could not start Python:`r`n`r`n$_", "Custom Robo") | Out-Null
    }
}

function Refresh-Build {
    if (-not $script:Proc) { return }
    $text = ""
    if (Test-Path $script:LogPath) {
        $text = Get-Content $script:LogPath -Tail 250 -ErrorAction SilentlyContinue | Out-String
    }
    $err = ""
    if (Test-Path $script:StderrPath) {
        $err = Get-Content $script:StderrPath -Tail 40 -ErrorAction SilentlyContinue | Out-String
    }
    if ($err) { $text = $text + "`r`n" + $err }
    if ($script:txtLog.Text -ne $text) {
        $script:txtLog.Text = $text
        $script:txtLog.SelectionStart = $script:txtLog.TextLength
        $script:txtLog.ScrollToCaret()
    }
    $script:lblStatus.Text = "Building... extracting, recompiling and compiling."
    if ($script:Proc.HasExited) {
        $script:Timer.Stop()
        $code = $script:Proc.ExitCode
        Set-Busy $false
        if ($code -eq 0) {
            $script:lblStatus.Text = "Build complete. Press Run."
        } else {
            $script:lblStatus.Text = "Build failed. See the log above."
            $msg = "The build failed (exit code $code).`r`n`r`n" + (Show-Log-Tail $script:LogPath 18)
            [System.Windows.Forms.MessageBox]::Show($msg, "Custom Robo") | Out-Null
        }
        $script:Proc = $null
    }
}

function Cancel-Build {
    if (-not $script:Proc) { return }
    try { taskkill /PID $script:Proc.Id /T /F | Out-Null } catch { }
    $script:Timer.Stop()
    Set-Busy $false
    $script:lblStatus.Text = "Build cancelled."
    $script:Proc = $null
}

function Save-Diagnostics([string]$Work) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $zip = Join-Path $Work "CustomRobo-diagnostics-$stamp.zip"
    $files = @()
    foreach ($name in @("build.log", "run.log", "keys.txt", "crash.log",
                        "launcher-stdout.txt", "launcher-stderr.txt",
                        "launcher-run.txt", "launcher-run-error.txt",
                        "diagnose-stdout.txt", "diagnose-stderr.txt")) {
        $p = Join-Path $Work $name
        if (Test-Path -LiteralPath $p) { $files += $p }
    }
    $files += @(Get-ChildItem -LiteralPath $Work -Filter "efb_*.png" -File -ErrorAction SilentlyContinue |
                ForEach-Object { $_.FullName })
    $files += @(Get-ChildItem -LiteralPath $Work -Filter "frame_*.png" -File -ErrorAction SilentlyContinue |
                ForEach-Object { $_.FullName })
    if ($files.Count -eq 0) { return $null }
    try {
        Compress-Archive -LiteralPath $files -DestinationPath $zip -Force -ErrorAction Stop
        return $zip
    } catch {
        return $null
    }
}

function Check-Diagnose {
    if (-not $script:DiagProc) { return }
    if (-not $script:DiagProc.HasExited) { return }
    $code = $script:DiagProc.ExitCode
    $script:DiagProc = $null
    $script:DiagTimer.Stop()
    $script:lblStatus.Text = "Diagnostics finished (exit $code); saving..."
    $work = $script:txtWork.Text.Trim()
    $zip = Save-Diagnostics $work
    if ($zip) {
        $script:lblStatus.Text = "Diagnostics saved."
        [System.Windows.Forms.MessageBox]::Show(
            "Diagnostics saved:`r`n$zip`r`n`r`nGame exit code: $code",
            "Custom Robo") | Out-Null
        Start-Process explorer.exe -ArgumentList "/select,`"$zip`""
    } else {
        $script:lblStatus.Text = "Diagnostics finished; no files were saved."
        [System.Windows.Forms.MessageBox]::Show(
            "The game exited with code $code, but no diagnostic files were found in:`r`n$work",
            "Custom Robo") | Out-Null
    }
}

function Start-Diagnose {
    if ($script:Building) { return }
    if ($script:DiagProc) {
        [System.Windows.Forms.MessageBox]::Show("A diagnostic run is already active.",
            "Custom Robo") | Out-Null
        return
    }
    $work = $script:txtWork.Text.Trim()
    $exe = Join-Path $work "recomp-build\wiiboot.exe"
    if (-not (Test-Path $exe)) {
        [System.Windows.Forms.MessageBox]::Show("The game has not been built yet. Press Build first.",
            "Custom Robo") | Out-Null
        return
    }
    $py = Ensure-Python
    if (-not $py) { return }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Save-Settings

    $env:CUSTOM_ROBO_BUNDLE = $script:Root
    $env:CUSTOM_ROBO_PROJECT = $script:ProjectRoot
    $env:PYTHONPATH = $script:ProjectRoot
    if ($script:txtSdl3.Text.Trim()) { $env:SDL3_DIR = $script:txtSdl3.Text.Trim() }
    if ($script:txtFonts.Text.Trim()) { $env:CUSTOM_ROBO_FONTS = $script:txtFonts.Text.Trim() }

    $out = Join-Path $work "diagnose-stdout.txt"
    $err = Join-Path $work "diagnose-stderr.txt"
    Remove-Item -Force -ErrorAction SilentlyContinue $out, $err

    $argv = @()
    $argv += $py.Prefix
    $argv += @($script:CorePath, "run", "--work", $work)
    if ($script:chkUnlock.Checked) { $argv += "--unlock" } else { $argv += "--no-unlock" }
    if ($script:txtSdl3.Text.Trim()) { $argv += @("--sdl3", $script:txtSdl3.Text.Trim()) }
    $line = (($argv | ForEach-Object { Format-Arg $_ }) -join " ")

    $diag = @{
        WIIKIT_DISCLOG = "1"
        WIIKIT_EFBDUMP = "120"
        WIIKIT_EFBDUMP_EVERY = "0"
        WIIKIT_EFBDUMP_STRIDE = "0"
        WIIKIT_GLDEBUG = "1"
    }
    if ($script:chkWhite.Checked) { $diag["WIIKIT_FORCEWHITE"] = "1" }
    $saved = @{}
    foreach ($key in $diag.Keys) {
        $saved[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        [Environment]::SetEnvironmentVariable($key, $diag[$key], "Process")
    }
    try {
        $script:DiagProc = Start-Process -FilePath $py.Exe -ArgumentList $line `
            -WorkingDirectory $script:Root -NoNewWindow -PassThru `
            -RedirectStandardOutput $out -RedirectStandardError $err
    } catch {
        $script:DiagProc = $null
        [System.Windows.Forms.MessageBox]::Show("Could not start the diagnostic run:`r`n`r`n$_",
            "Custom Robo") | Out-Null
    } finally {
        foreach ($key in $diag.Keys) {
            [Environment]::SetEnvironmentVariable($key, $saved[$key], "Process")
        }
    }
    if ($script:DiagProc) {
        $script:DiagTimer.Start()
        $script:lblStatus.Text = "Diagnostics running. Close the game when you are done."
    }
}

function Start-Game {
    if ($script:Building) { return }
    $work = $script:txtWork.Text.Trim()
    $exe = Join-Path $work "recomp-build\wiiboot.exe"
    if (-not (Test-Path $exe)) {
        [System.Windows.Forms.MessageBox]::Show("The game has not been built yet. Press Build first.", "Custom Robo") | Out-Null
        return
    }
    $py = Ensure-Python
    if (-not $py) { return }
    $env:CUSTOM_ROBO_BUNDLE = $script:Root
    $env:CUSTOM_ROBO_PROJECT = $script:ProjectRoot
    $env:PYTHONPATH = $script:ProjectRoot
    if ($script:txtSdl3.Text.Trim()) { $env:SDL3_DIR = $script:txtSdl3.Text.Trim() }
    if ($script:txtFonts.Text.Trim()) { $env:CUSTOM_ROBO_FONTS = $script:txtFonts.Text.Trim() }

    $out = Join-Path $work "launcher-run.txt"
    $err = Join-Path $work "launcher-run-error.txt"
    Remove-Item -Force -ErrorAction SilentlyContinue $out, $err

    $argv = @()
    $argv += $py.Prefix
    $argv += @($script:CorePath, "fonts", "--work", $work)
    if ($script:txtFonts.Text.Trim()) { $argv += @("--source", $script:txtFonts.Text.Trim()) }
    $fontLine = (($argv | ForEach-Object { Format-Arg $_ }) -join " ")
    $p = Start-Process -FilePath $py.Exe -ArgumentList $fontLine -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -WorkingDirectory $script:Root
    if ($p.ExitCode -ne 0) {
        $msg = "The console fonts could not be installed.`r`n`r`n" +
               (Get-Content $err -Raw -ErrorAction SilentlyContinue) + "`r`n" +
               (Get-Content $out -Raw -ErrorAction SilentlyContinue)
        [System.Windows.Forms.MessageBox]::Show($msg, "Custom Robo") | Out-Null
        return
    }

    $argv = @()
    $argv += $py.Prefix
    $argv += @($script:CorePath, "run", "--work", $work, "--detach")
    if ($script:chkUnlock.Checked) { $argv += "--unlock" } else { $argv += "--no-unlock" }
    if ($script:txtSdl3.Text.Trim()) { $argv += @("--sdl3", $script:txtSdl3.Text.Trim()) }
    $runLine = (($argv | ForEach-Object { Format-Arg $_ }) -join " ")
    $p = Start-Process -FilePath $py.Exe -ArgumentList $runLine -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err -WorkingDirectory $script:Root
    if ($p.ExitCode -ne 0) {
        $msg = "The game could not start.`r`n`r`n" +
               (Get-Content $err -Raw -ErrorAction SilentlyContinue) + "`r`n" +
               (Show-Log-Tail (Join-Path $work "run.log") 20)
        [System.Windows.Forms.MessageBox]::Show($msg, "Custom Robo") | Out-Null
        return
    }
    $script:lblStatus.Text = "Custom Robo is running."
}

$form.Add_FormClosing({
    param($sender, $e)
    if ($script:Building) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "A build is still running. Cancel it and quit?", "Custom Robo",
            [System.Windows.Forms.MessageBoxButtons]::YesNo)
        if ($r -ne "Yes") { $e.Cancel = $true; return }
        Cancel-Build
    }
})

# Start with a sane status if a build already exists.
if (Test-Path (Join-Path $script:txtWork.Text "recomp-build\wiiboot.exe")) {
    $script:lblStatus.Text = "A build is ready. Press Run, or choose a disc image and press Build."
}

[void]$form.ShowDialog()
