#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PublishDirectory,

    [Parameter(Mandatory = $true)]
    [string]$LauncherSourcePath,

    [Parameter(Mandatory = $true)]
    [string]$UninstallerSourcePath,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$FileVersion
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$publishDirectoryPath = (Resolve-Path -LiteralPath $PublishDirectory).Path
$launcherSourceFilePath = (Resolve-Path -LiteralPath $LauncherSourcePath).Path
$uninstallerSourceFilePath = (Resolve-Path -LiteralPath $UninstallerSourcePath).Path
$legacyOwnedFilesPath = (Resolve-Path -LiteralPath (
    Join-Path $PSScriptRoot '../../windows/installer/Sidey.Setup/LegacyV131OwnedFiles.txt')).Path
$runtimeDirectory = Join-Path $publishDirectoryPath 'Runtime'
$assetsDirectory = Join-Path $publishDirectoryPath 'Assets'
$languageDirectory = Join-Path $publishDirectoryPath 'Langs'
$legacyLanguageDirectory = Join-Path $publishDirectoryPath 'Lang'
$launcherPath = Join-Path $publishDirectoryPath 'SIDEY.exe'
$uninstallerPath = Join-Path $publishDirectoryPath 'Uninstall.exe'
$hostPath = Join-Path $runtimeDirectory 'SIDEY.Host.exe'

if (Test-Path -LiteralPath $runtimeDirectory) {
    $runtimeParent = [IO.Directory]::GetParent($runtimeDirectory).FullName
    if (-not [string]::Equals(
        $runtimeParent,
        $publishDirectoryPath,
        [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe Runtime directory: $runtimeDirectory"
    }
    Remove-Item -LiteralPath $runtimeDirectory -Recurse -Force
}
[IO.Directory]::CreateDirectory($runtimeDirectory) | Out-Null
[IO.Directory]::CreateDirectory($languageDirectory) | Out-Null

if (Test-Path -LiteralPath $legacyLanguageDirectory -PathType Container) {
    Get-ChildItem -LiteralPath $legacyLanguageDirectory -Force |
        ForEach-Object {
            Move-Item -LiteralPath $_.FullName -Destination $languageDirectory -Force
        }
    Remove-Item -LiteralPath $legacyLanguageDirectory -Force
}

foreach ($catalogName in @(
    'ko-KR.json',
    'en-US.json',
    'ja-JP.json',
    'zh-CN.json',
    'zh-TW.json',
    'uk-UA.json',
    'ru-RU.json',
    'it-IT.json',
    'pt-PT.json',
    'es-ES.json',
    'cs-CZ.json',
    'tr-TR.json',
    'ro-RO.json',
    'bg-BG.json',
    'pt-BR.json',
    'sr-Cyrl-RS.json',
    'pl-PL.json',
    'sr-Latn-RS.json',
    'nl-BE.json',
    'fr-FR.json',
    'nl-NL.json',
    'he-IL.json',
    'de-DE.json')) {
    $catalogPath = Join-Path $languageDirectory $catalogName
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
        throw "Published language catalog is missing: $catalogPath"
    }
}

$preservedNames = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($name in @(
    'Assets',
    'InternalLangs',
    'Langs',
    'Runtime')) {
    [void]$preservedNames.Add($name)
}

Get-ChildItem -LiteralPath $publishDirectoryPath -Force |
    Where-Object { -not $preservedNames.Contains($_.Name) } |
    ForEach-Object {
        Move-Item -LiteralPath $_.FullName -Destination $runtimeDirectory -Force
    }

$publishedHost = Join-Path $runtimeDirectory 'SIDEY.Host.exe'
if (-not (Test-Path -LiteralPath $publishedHost -PathType Leaf)) {
    throw "Published WinUI host is missing: $publishedHost"
}
$legacyHost = Join-Path $runtimeDirectory 'SIDEY.exe'
$legacyAssembly = Join-Path $runtimeDirectory 'SIDEY.dll'
if (Test-Path -LiteralPath $legacyHost -PathType Leaf) {
    Remove-Item -LiteralPath $legacyHost -Force
}
if (Test-Path -LiteralPath $legacyAssembly -PathType Leaf) {
    Remove-Item -LiteralPath $legacyAssembly -Force
}

if (-not (Test-Path -LiteralPath $assetsDirectory -PathType Container)) {
    throw "Published Assets directory is missing: $assetsDirectory"
}
# Compiled PRI/XAML stays beside the host. File assets, including the title bar
# icon, are loaded explicitly from the deployment root; no private copy is needed.

$installerLanguagesSourcePath = (Resolve-Path -LiteralPath (
    Join-Path $PSScriptRoot '..\..\windows\installer\Sidey.Setup\InstallerLanguages.cs')).Path
$helperBuilder = Join-Path $PSScriptRoot 'New-SideyHelperExecutable.ps1'
$iconPath = Join-Path $assetsDirectory 'Icons\SideyAppIcon.ico'

& $helperBuilder `
    -SourcePath @($launcherSourceFilePath, $installerLanguagesSourcePath) `
    -OutputPath $launcherPath `
    -Version $Version -FileVersion $FileVersion -IconPath $iconPath `
    -Title 'SIDEY Launcher' `
    -Description 'SIDEY desktop launcher'
& $helperBuilder `
    -SourcePath $uninstallerSourceFilePath `
    -OutputPath $uninstallerPath `
    -ResourcePath $legacyOwnedFilesPath -ResourceName 'SIDEY.LegacyV131OwnedFiles.txt' `
    -Version $Version -FileVersion $FileVersion -IconPath $iconPath `
    -Title 'SIDEY Uninstaller' `
    -Description 'SIDEY uninstaller'

Write-Host "PublishLayout=SIDEY.exe + Uninstall.exe + Assets + Langs + Runtime/SIDEY.Host.exe"
