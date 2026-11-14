# Installs the exact Godot version this project uses into tools\godot\.
# Run through tools\setup.cmd. Safe to run again: it skips the download if Godot is present.

$ErrorActionPreference = 'Stop'
$version = '4.4.1-stable'
$zipName = "Godot_v${version}_win64.exe.zip"
$url = "https://github.com/godotengine/godot/releases/download/$version/$zipName"
# SHA-512 of the official zip, so a corrupted or tampered download is refused.
$expectedHash = '266978B803F7532EDC69BDD5D8C4FDCED0EA97AEF1224A8879616398A2559E135520E186ADD06B532AA92BDFEECF6AC024634024DE4B3ABD69F6C34E6D6D0563'
# Official Godot builds are signed by this company.
$expectedSigner = 'Prehensile Tales B.V.'

$godotDir = Join-Path $PSScriptRoot 'godot'
$exe = Join-Path $godotDir "Godot_v${version}_win64.exe"

if (Test-Path $exe) {
    Write-Host "Godot $version is already installed in $godotDir"
    exit 0
}

New-Item -ItemType Directory -Force $godotDir | Out-Null
$zip = Join-Path $env:TEMP $zipName
Write-Host "Downloading $url"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing

$hash = (Get-FileHash -Algorithm SHA512 -LiteralPath $zip).Hash
if ($hash -ne $expectedHash) {
    Remove-Item -LiteralPath $zip -Force
    throw "Downloaded file does not match the official Godot $version build. Nothing was installed."
}

Expand-Archive -LiteralPath $zip -DestinationPath $godotDir -Force
Remove-Item -LiteralPath $zip -Force

foreach ($file in Get-ChildItem -LiteralPath $godotDir -Filter *.exe) {
    $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch [regex]::Escape($expectedSigner)) {
        Remove-Item -LiteralPath $godotDir -Recurse -Force
        throw "$($file.Name) is not signed by $expectedSigner. Nothing was installed."
    }
}

Write-Host "Installed Godot $version in $godotDir"
Write-Host "Next: run tools\test.cmd to check everything works."
