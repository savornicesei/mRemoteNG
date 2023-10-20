function Invoke-VsDevCmd {
    <#
    .SYNOPSIS 
    Sets environment variables from VsDevCmd without creating a nested prompt (so that resgen.exe can be located)
    .PARAMETER ToolsDir
    Path to the tools folder (where vswhere.exe is located for Windows builds)
    .LINK
    https://github.com/Microsoft/vswhere/wiki/Start-Developer-Command-Prompt#using-powershell
    #>
    param(
        [Parameter(HelpMessage = 'Path to tools folder')]
        [string] $ToolsDir
    )

    Write-Build DarkBlue "Setup of VsDevCmd starting..."

    if($IsWindows)
    {
        #set environment variables from VsDevCmd without creating a nested prompt 
        $installationPath = & $(Join-Path $ToolsDir 'vswhere.exe') -prerelease -latest -property installationPath
        Write-Output "Visual Studio install folder: $installationPath"
        if ($installationPath -and (Test-Path "$installationPath\Common7\Tools\vsdevcmd.bat")) {
        & "${env:COMSPEC}" /s /c "`"$installationPath\Common7\Tools\vsdevcmd.bat`" -no_logo && set" | ForEach-Object {
            $name, $value = $_ -split '=', 2
            Set-Content env:\"$name" $value
            }
        }

        $cscVersion = & csc /version
        Write-Output "csc version: $cscVersion"
    }
    else {
        Write-Output "Not on Windows. Nothing to do"
    }

    Write-Build DarkBlue "Setup of VsDevCmd completed"
}
function Get-MsBuild {
    <#
    .SYNOPSIS 
    Gets the path to latest 'MSBuild'
    .PARAMETER ToolsDir
    Path to the tools folder (where vswhere.exe is located for Windows builds)
    #>
    param(
        [Parameter(HelpMessage = 'Path to tools folder')]
        [string] $ToolsDir
    )

    # for TFMs less than net462, use MSBuild (provided by .NET Framework or mono)
    # see https://halfblood.pro/locate-msbuild-via-powershell-on-different-operating-systems-140757bb8e18
    $msBuild_exe = "msbuild"
    if($IsWindows) {
        $vswhere_exe = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if(-not (Test-Path -LiteralPath $vswhere_exe)) {
            $vswhere_exe = Join-Path $toolsDir "wswhere.exe"
        }
        $msBuild_exe = & $VSWHERE_EXE -latest -products * -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe | Select-Object -first 1

        #TODO: Detect Mono on Windows
    }

    return $msBuild_exe
}