#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PublishDirectory,
    [Parameter(Mandatory = $true)][string]$SelectorExecutablePath,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$FileVersion,
    [Parameter(Mandatory = $true)][string]$NsisDirectory
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$builder = Join-Path $PSScriptRoot '../New-SideyHelperExecutable.ps1'
$icon = Join-Path $root 'windows/src/Sidey.App/Assets/Icons/SideyAppIcon.ico'
# A fresh directory forces independent compilation and exercises paths with spaces.
$probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('SIDEY helper verification ' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($probeRoot)
$languages = Join-Path $root 'windows/installer/Sidey.Setup/InstallerLanguages.cs'
$helpers = @(
    @{ Name = 'SIDEY.exe'; Title = 'SIDEY Launcher'; Description = 'SIDEY desktop launcher';
       Sources = @((Join-Path $root 'windows/src/Sidey.Launcher/Program.cs'), $languages);
       Original = (Join-Path $PublishDirectory 'SIDEY.exe') },
    @{ Name = 'Uninstall.exe'; Title = 'SIDEY Uninstaller'; Description = 'SIDEY uninstaller';
       Sources = @((Join-Path $root 'windows/src/Sidey.Uninstaller/Program.cs'));
       Resource = (Join-Path $root 'windows/installer/Sidey.Setup/LegacyV131OwnedFiles.txt');
       Original = (Join-Path $PublishDirectory 'Uninstall.exe') },
    @{ Name = 'Sidey.SetupLanguage.exe'; Title = 'SIDEY Installer Language';
       Original = $SelectorExecutablePath }
)

foreach ($helper in $helpers) {
    $rebuilt = Join-Path $probeRoot $helper.Name
    if ($helper.Name -eq 'Sidey.SetupLanguage.exe') {
        # Use a fresh PowerShell process because the dialog resource reader is a
        # build-time Add-Type helper with a process-wide type name.
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
            -File (Join-Path $PSScriptRoot '../New-InstallerLanguageSelector.ps1') `
            -OutputPath $rebuilt -Version $Version -FileVersion $FileVersion -NsisDirectory $NsisDirectory
        if ($LASTEXITCODE -ne 0) { throw 'Independent language selector build failed.' }
    }
    else {
        $buildArguments = @{
            SourcePath = $helper.Sources
            OutputPath = $rebuilt
            Title = $helper.Title
            Description = $helper.Description
            Version = $Version
            FileVersion = $FileVersion
            IconPath = $icon
        }
        if ($helper.ContainsKey('Resource')) {
            $buildArguments.ResourcePath = $helper.Resource
            $buildArguments.ResourceName = 'SIDEY.LegacyV131OwnedFiles.txt'
        }
        & $builder @buildArguments
    }

    $original = (Resolve-Path -LiteralPath $helper.Original).Path
    $originalHash = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
    $rebuiltHash = (Get-FileHash -LiteralPath $rebuilt -Algorithm SHA256).Hash
    if ($originalHash -cne $rebuiltHash) {
        throw "Helper is not reproducible from the current sources: $($helper.Name)"
    }
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($original)
    if ($info.ProductName -cne 'SIDEY' -or $info.CompanyName -cne 'SIDEY' -or
        $info.FileVersion -cne $FileVersion -or $info.ProductVersion -cne $Version -or
        $info.FileDescription -cne $helper.Title) {
        throw "Helper product/version metadata does not match: $($helper.Name)"
    }
    if ([Reflection.AssemblyName]::GetAssemblyName($original).Version.ToString() -cne $FileVersion) {
        throw "Helper assembly version does not match: $($helper.Name)"
    }
    Write-Host "Verified helper $($helper.Name) SHA256=$originalHash"
}

# These modes do not show windows, install anything, remove data, or change settings.
foreach ($language in @(1033, 1042, 1041, 2052, 1028, 1049, 1058)) {
    $process = Start-Process -FilePath (Join-Path $probeRoot 'Sidey.SetupLanguage.exe') `
        -ArgumentList @([string]$language, '0', '--silent') -WindowStyle Hidden -PassThru -Wait
    if ($process.ExitCode -ne $language) { throw "Language selection exit code changed: $language" }
}
$process = Start-Process -FilePath (Join-Path $probeRoot 'Uninstall.exe') `
    -ArgumentList '--sidey-invalid-verification-argument' -WindowStyle Hidden -PassThru -Wait
if ($process.ExitCode -ne 64) { throw 'Uninstaller no longer rejects unsupported arguments.' }
$uninstallerAssembly = [Reflection.Assembly]::Load(
    [IO.File]::ReadAllBytes((Join-Path $probeRoot 'Uninstall.exe')))
$uninstallerProgram = $uninstallerAssembly.GetType('Sidey.Uninstaller.Program', $true)
$errorMapper = $uninstallerProgram.GetMethod(
    'GetDesktopUserRunnerErrorCode',
    [Reflection.BindingFlags]'NonPublic,Static')
$mappedError = [int]$errorMapper.Invoke(
    $null,
    [object[]]@([ComponentModel.Win32Exception]::new(193)))
if ($mappedError -ne 193) {
    throw "Desktop-user runner did not preserve ERROR_BAD_EXE_FORMAT (193): $mappedError"
}
# Exercise the compiled helper with temporary data and an injected startup
# writer. Never read or change this machine's real Run key or SIDEY user data.
$completion = $uninstallerProgram.GetMethod(
    'ApplyInstallationCompletion',
    [Reflection.BindingFlags]'NonPublic,Static')
$startupProbe = @{ Calls = 0; Result = 0 }
$startupWriter = [Func[int]]{
    $startupProbe.Calls++
    return [int]$startupProbe.Result
}
$relocationProbe = @{ Calls = 0; Result = 0 }
$relocationWriter = [Func[int]]{
    $relocationProbe.Calls++
    return [int]$relocationProbe.Result
}
function Invoke-CompletionProbe([string]$Kind, [string]$Id, [string]$Directory) {
    return [int]$completion.Invoke($null, [object[]]@(
        [string[]]@($Kind, '9.8.7', $Id), $Directory, $startupWriter, $relocationWriter))
}
$freshData = Join-Path $probeRoot 'fresh user data'
if ((Invoke-CompletionProbe 'fresh' 'fresh-1' $freshData) -ne 0 -or $startupProbe.Calls -ne 1) {
    throw 'Fresh setup did not enable startup once.'
}
if ((Invoke-CompletionProbe 'fresh' 'fresh-1' $freshData) -ne 0 -or $startupProbe.Calls -ne 1) {
    throw 'Committed recovery repeated startup registration.'
}
$pendingUpdate = Join-Path $freshData 'pending-installed-update.txt'
if (Test-Path -LiteralPath $pendingUpdate) { throw 'Fresh setup reported an update.' }
if ((Invoke-CompletionProbe 'upgrade' 'upgrade-1' $freshData) -ne 0 -or $startupProbe.Calls -ne 1) {
    throw 'Upgrade overwrote the existing startup choice.'
}
if ([IO.File]::ReadAllText($pendingUpdate) -cne '9.8.7') {
    throw 'Upgrade did not record the installed version.'
}
[IO.File]::Delete($pendingUpdate)
if ((Invoke-CompletionProbe 'upgrade' 'upgrade-1' $freshData) -ne 0 -or
    (Test-Path -LiteralPath $pendingUpdate)) {
    throw 'Recovery reposted a consumed update notification.'
}
if ((Invoke-CompletionProbe 'repair' 'repair-1' $freshData) -ne 0 -or $startupProbe.Calls -ne 1 -or
    (Test-Path -LiteralPath $pendingUpdate)) {
    throw 'Repair changed startup or reported an update.'
}
$relocationData = Join-Path $probeRoot 'relocated user data'
$relocationProbe.Result = 5
if ((Invoke-CompletionProbe 'relocate' 'relocate-1' $relocationData) -ne 5 -or
    (Test-Path -LiteralPath (Join-Path $relocationData 'last-completed-install.txt'))) {
    throw 'Failed relocation startup refresh was marked complete.'
}
$relocationProbe.Result = 0
if ((Invoke-CompletionProbe 'relocate' 'relocate-1' $relocationData) -ne 0 -or
    $relocationProbe.Calls -ne 2 -or $startupProbe.Calls -ne 1) {
    throw 'Relocation did not refresh an enabled startup entry without enabling startup.'
}
if ([IO.File]::ReadAllText((Join-Path $relocationData 'pending-installed-update.txt')) -cne '9.8.7') {
    throw 'Relocation did not report the installed update.'
}
if ((Invoke-CompletionProbe 'relocate' 'relocate-1' $relocationData) -ne 0 -or
    $relocationProbe.Calls -ne 2) {
    throw 'Recovery repeated the relocation startup refresh.'
}
$retryData = Join-Path $probeRoot 'retry user data'
$startupProbe.Result = 5
if ((Invoke-CompletionProbe 'fresh' 'retry-1' $retryData) -ne 5 -or
    (Test-Path -LiteralPath (Join-Path $retryData 'last-completed-install.txt'))) {
    throw 'A failed startup registration was marked complete.'
}
$startupProbe.Result = 0
if ((Invoke-CompletionProbe 'fresh' 'retry-1' $retryData) -ne 0 -or $startupProbe.Calls -ne 3) {
    throw 'Recovery did not retry failed startup registration.'
}

# The legacy cleanup deletes only verified payload files after a committed
# relocation. Inject a small manifest so the test never depends on a release
# download or touches an actual installation.
$legacyCleanup = $uninstallerProgram.GetMethod(
    'CleanupLegacyInstallFiles',
    [Reflection.BindingFlags]'NonPublic,Static')
$oldParent = Join-Path $probeRoot 'old location'
$oldInstall = Join-Path $oldParent 'SIDEY'
$newInstall = Join-Path $probeRoot 'new SIDEY'
[IO.Directory]::CreateDirectory((Join-Path $oldInstall 'Assets')) | Out-Null
[IO.Directory]::CreateDirectory($newInstall) | Out-Null
$oldLauncher = Join-Path $oldInstall 'SIDEY.exe'
$oldAsset = Join-Path $oldInstall 'Assets\owned.txt'
$unknown = Join-Path $oldInstall 'unrelated.txt'
[IO.File]::WriteAllText($oldLauncher, 'legacy launcher')
[IO.File]::WriteAllText($oldAsset, 'owned asset')
[IO.File]::WriteAllText($unknown, 'user file')
$owned = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
$owned.Add('SIDEY.exe', (Get-FileHash -LiteralPath $oldLauncher -Algorithm SHA256).Hash)
$owned.Add('Assets\owned.txt', (Get-FileHash -LiteralPath $oldAsset -Algorithm SHA256).Hash)
function Invoke-LegacyCleanup([string]$OldPath, [string]$NewPath) {
    return [int]$legacyCleanup.Invoke($null, [object[]]@($OldPath, $NewPath, $owned))
}
if ((Invoke-LegacyCleanup $oldInstall (Join-Path $oldInstall 'new')) -ne 1 -or
    -not (Test-Path -LiteralPath $oldLauncher)) {
    throw 'Legacy cleanup accepted a path containing the new installation.'
}
$transaction = $oldInstall + '.sidey-transaction.json'
[IO.File]::WriteAllText($transaction, 'pending')
if ((Invoke-LegacyCleanup $oldInstall $newInstall) -ne 1 -or
    -not (Test-Path -LiteralPath $oldAsset)) {
    throw 'Legacy cleanup touched a directory with pending transaction state.'
}
[IO.File]::Delete($transaction)
if ((Invoke-LegacyCleanup $oldInstall $newInstall) -ne 1 -or
    (Test-Path -LiteralPath $oldLauncher) -or (Test-Path -LiteralPath $oldAsset) -or
    -not (Test-Path -LiteralPath $unknown)) {
    throw 'Legacy cleanup did not preserve an unrelated file while deleting verified payload.'
}
[IO.File]::WriteAllText($oldLauncher, 'modified launcher')
if ((Invoke-LegacyCleanup $oldInstall $newInstall) -ne 1 -or
    -not (Test-Path -LiteralPath $oldLauncher)) {
    throw 'Legacy cleanup accepted a modified launcher.'
}
[IO.File]::Delete($oldLauncher)
[IO.File]::Delete($unknown)
[IO.File]::WriteAllText($oldLauncher, 'legacy launcher')
if ((Invoke-LegacyCleanup $oldInstall $newInstall) -ne 0 -or
    (Test-Path -LiteralPath $oldInstall)) {
    throw 'Legacy cleanup did not remove an empty verified installation.'
}
Write-Host "Helper verification passed. Evidence directory: $probeRoot"
