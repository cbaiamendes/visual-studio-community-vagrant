function Install-ModifiedChocolateyPackage($name, $version, $checksum, [scriptblock]$modifier) {
    $archiveUrl = "https://packages.chocolatey.org/$name.$version.nupkg"
    $archiveHash = $checksum
    $archiveName = Split-Path $archiveUrl -Leaf
    $archivePath = "$env:TEMP\$archiveName.zip"
    Write-Host "Downloading the $name package..."
    (New-Object Net.WebClient).DownloadFile($archiveUrl, $archivePath)
    $archiveActualHash = (Get-FileHash $archivePath -Algorithm SHA256).Hash
    if ($archiveHash -ne $archiveActualHash) {
        throw "$archiveName downloaded from $archiveUrl to $archivePath has $archiveActualHash hash witch does not match the expected $archiveHash"
    }
    Expand-Archive $archivePath "$archivePath.tmp"
    Push-Location "$archivePath.tmp"
    Remove-Item -Recurse _rels,package,*.xml
    &$modifier
    choco pack
    choco install -y $name -Source $PWD
    Pop-Location
}

# add support for building applications that target the .net 4.7.2 framework.
# NB we have to install netfx-4.7.2-devpack manually, because for some odd reason,
#    the setup is returning the -1073741819 (0xc0000005 STATUS_ACCESS_VIOLATION)
#    exit code even thou it installs successfully.
Install-ModifiedChocolateyPackage netfx-4.7.2-devpack 4.7.2.20180712 142a56fa770f6398156ad6cd6c3c0f8a6aed91697b20fd3a96daa457a58d40e4 {
    Set-Content -Encoding Ascii `
        tools/ChocolateyInstall.ps1 `
        ((Get-Content tools/ChocolateyInstall.ps1) -replace '0, # success','0,-1073741819, # success')
}

# add support for building applications that target the .net 4.7.1 framework.
# NB we have to install netfx-4.7.1-devpack manually, because for some odd reason,
#    the setup is returning the -1073741819 (0xc0000005 STATUS_ACCESS_VIOLATION)
#    exit code even thou it installs successfully.
#    see https://github.com/jberezanski/ChocolateyPackages/issues/22
Install-ModifiedChocolateyPackage netfx-4.7.1-devpack 4.7.2558.0 e293769f03da7a42ed72d37a92304854c4a61db279987fc459d3ec7aaffecf93 {
    Set-Content -Encoding Ascii `
        tools/ChocolateyInstall.ps1 `
        ((Get-Content tools/ChocolateyInstall.ps1) -replace '0, # success','0,-1073741819, # success')
    # do not depend on dotnet, as we already installed a recent version of dotnet from another package.
    Set-Content -Encoding Ascii `
        netfx-4.7.1-devpack.nuspec `
        ((Get-Content netfx-4.7.1-devpack.nuspec) -replace '.+dotnet4.7.1.+','')
}

# add support for building applications that target the .net 4.6.2 framework.
choco install -y netfx-4.6.2-devpack

# see https://www.visualstudio.com/vs/
# see https://docs.microsoft.com/en-us/visualstudio/releases/2019/release-notes
# see https://docs.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio
# see https://docs.microsoft.com/en-us/visualstudio/install/command-line-parameter-examples
# see https://docs.microsoft.com/en-us/visualstudio/install/workload-and-component-ids
$archiveUrl = 'https://download.visualstudio.microsoft.com/download/pr/1b6e9bcd-b9f0-45ec-848d-b91d7ac62659/f63d5e9540570c877020913190317949/vs_community.exe'
$archiveHash = 'b797bf28822d8fa914ff1b6f18d13bf30a58e775366063ada5fc497e1d864b70'
$archiveName = Split-Path $archiveUrl -Leaf
$archivePath = "$env:TEMP\$archiveName"
Write-Host 'Downloading the Visual Studio Setup Bootstrapper...'
(New-Object Net.WebClient).DownloadFile($archiveUrl, $archivePath)
$archiveActualHash = (Get-FileHash $archivePath -Algorithm SHA256).Hash
if ($archiveHash -ne $archiveActualHash) {
    throw "$archiveName downloaded from $archiveUrl to $archivePath has $archiveActualHash hash witch does not match the expected $archiveHash"
}
Write-Host 'Installing Visual Studio...'
$vsHome = 'C:\VisualStudio2019Community'
# NB the Windows 10 SDK 17763 must be compatible with the Windows 10 WDK that we install in provision-wdk.ps1.
for ($try = 1; ; ++$try) {
    &$archivePath `
        --installPath $vsHome `
        --add Microsoft.VisualStudio.Workload.CoreEditor `
        --add Microsoft.VisualStudio.Workload.NetCoreTools `
        --add Microsoft.VisualStudio.Workload.NetWeb `
        --add Microsoft.VisualStudio.Workload.ManagedDesktop `
        --add Microsoft.VisualStudio.Workload.NativeDesktop `
        --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        --add Microsoft.VisualStudio.Component.Windows10SDK.17763 `
        --norestart `
        --quiet `
        --wait `
        | Out-String -Stream
    if ($LASTEXITCODE) {
        if ($try -le 5) {
            Write-Host "Failed to install Visual Studio with Exit Code $LASTEXITCODE. Trying again (hopefully the error was transient)..."
            Start-Sleep -Seconds 10
            continue
        }
        throw "Failed to install Visual Studio with Exit Code $LASTEXITCODE"
    }
    break
}

# add MSBuild to the machine PATH.
[Environment]::SetEnvironmentVariable(
    'PATH',
    "$([Environment]::GetEnvironmentVariable('PATH', 'Machine'));$vsHome\MSBuild\Current\Bin",
    'Machine')
