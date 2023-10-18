<#
.SYNOPSIS
mRemoteNG build script.

.DESCRIPTION
Build script for mRemoteNG

.PARAMETER Tasks
One or more execution tasks(s), similar to NAnt or Cake targets as a string of tasks divided by comma

.PARAMETER BuildConfiguration
MSBuild  build configuration - defines the settings that will be used at run time. Valid choices are Debug, Release, Debug Portable, Release Portable, Release Installer.

.PARAMETER Rebuild
Rebuilds the solution. Default is to do a simple build.

.PARAMETER WithCoverage
Includes coverage when running tests. Default is false.

.PARAMETER FailWhenTestsFail
Fail the build if at least one test failed. Default is true.


.RELEASENOTES
  1.0.0 - Initial version
#>

#Requires -Version 7.0
#Requires -PSEdition Core

#####################################
#Required script parameters
#####################################
param(
    [Parameter(Position=0, HelpMessage = "One or more execution tasks(s), similar to NAnt or Cake targets")]
	[string[]]$Tasks,

    [Parameter(HelpMessage = "MSBuild  build configuration - defines the settings that will be used at run time. Valid choices are Debug, Release, Debug Portable, Debug Installer, Release Portable, Release Installer,Release Installer and Portable")]  
    [ValidateSet('Debug', 'Release', 'Debug Portable', 'Debug Installer', 'Release Portable', 'Release Installer', 'Release Installer and Portable', IgnoreCase = $true, ErrorMessage="Value '{0}' is invalid. Try one of: '{1}'")]
    [string] $BuildConfiguration = 'Debug',

    [Parameter(HelpMessage = 'Rebuilds the solution')]
    [switch] $Rebuild,

    [Parameter(HelpMessage = 'Includes coverage when running tests')]
    [switch] $WithCoverage = $false
)

Set-StrictMode -Version latest

#####################################################
#      initialization: Invoke-Build module
#####################################################
if ($MyInvocation.ScriptName -notlike '*Invoke-Build.ps1') {
	$ErrorActionPreference = 'Stop'
    $policy = (Get-PSRepository PSGallery).InstallationPolicy
	try {
		Import-Module InvokeBuild
	}
	catch {
        Set-PSRepository PSGallery -InstallationPolicy Trusted
		Install-Module InvokeBuild -Scope CurrentUser -Force -Repository PSGallery -SkipPublisherCheck -Verbose
		Import-Module InvokeBuild
	}
    finally {
        Set-PSRepository PSGallery -InstallationPolicy $policy
    }
    
    try {
        Invoke-Build -Task $Tasks -File $MyInvocation.MyCommand.Path @PSBoundParameters
    } 
    catch { 
        $PSItem | Format-List * -Force | Out-String
        $LASTEXITCODE = 1
    }
    if(0 -ne $LASTEXITCODE)
    {
        Write-Host "Exit code: $LASTEXITCODE" -ForegroundColor Red
    }
    exit $LASTEXITCODE
}

#####################################################
#         initialization: global variables
#####################################################
# is CI build on Appveyor
$IS_CI_APPVEYOR = $null -ne $env:APPVEYOR
# is CI build on GitHub
$IS_CI_GITHUB = $true -eq $env:GITHUB_ACTIONS
# is CI build, either on Appveyor or on GitHub
$IS_CI_BUILD = $IS_CI_APPVEYOR -or $IS_CI_GITHUB

$TOOLS_DIR = Join-Path $BuildRoot "Tools"
$REPORTS_DIR = Join-Path $BuildRoot "reports"

#MSBuild paralelism
$parallelism = 3
#MSBuild verbosity: q[uiet], m[inimal], n[ormal] (default), d[etailed], and diag[nostic]
$verbosity = 'm'

#####################################################
#      initialization: before build
#####################################################
Enter-Build {
    Write-Build Blue "
    is CI build: $IS_CI_BUILD,
    Build configuration: $BuildConfiguration,
    Tools directory: $TOOLS_DIR,
    Reports directory: $REPORTS_DIR"
}

#####################################
#          Tasks
#####################################
task Init {
    <#
    .SYNOPSIS
    Initialization of any folder structure of files required for a succesful build
    #>
    Write-Build Cyan '----------------------------------------------------------------------------------'
    Write-Build Cyan '[Init] Initiating build process for mRemoteNG project'
    Write-Build Cyan '----------------------------------------------------------------------------------'

    Write-Output '[Init] Preparing to run build script'

    # Make sure reports folder exists
    if ((Test-Path $BuildRoot) -and !(Test-Path $REPORTS_DIR)) {
        Write-Output "[Init] Creating reports directory..."
        New-Item -Path $REPORTS_DIR -Type Directory -Force | Out-Null
    }

    Write-Output "[Init] Installing dotnet tools"
    exec { & dotnet tool restore }
}

task Clean {
    <#
    .SYNOPSIS 
    Executes any cleanup required before building the project.
    #>
    Write-Build Cyan '----------------------------------------------------------------------------------'
    Write-Build Cyan '[Clean] Starting cleanup of mRemoteNG project'
    Write-Build Cyan '----------------------------------------------------------------------------------'
    
    Write-Output '[Clean] Cleaning reports folder except NDepend one'
    if (Test-Path $REPORTS_DIR ) {
        Write-Output -Message "[Clean] Cleaning reports directory..."
        Get-ChildItem -Path $REPORTS_DIR -Exclude NDependOut | Remove-Item -Recurse -Force -ErrorAction Ignore
    }

    Write-Output '[Clean] Cleaning output of dotnet projects'
    exec { & dotnet clean }
}

task CleanBinObj {
    <#
    .SYNOPSIS 
    Cleans all /bin and /obj folders
    #>
    Write-Build Cyan '----------------------------------------------------------------------------------'
    Write-Build Cyan '[Clean] Starting cleanup of mRemoteNG project /bin and /obj folders'
    Write-Build Cyan '----------------------------------------------------------------------------------'

    Write-Output "[Deep-Clean] Cleaning /bin and /obj folders from $BuildRoot"
    Get-ChildItem $BuildRoot -Include bin,obj -Recurse | Remove-Item -Recurse -Force -ErrorAction Ignore
}

task InstallDeps {
    <#
    .SYNOPSIS
    Installs mRemoteNG shared dependencies.
    #>
    Write-Build Cyan '----------------------------------------------------------------------------------'
    Write-Build Cyan '[Build] Starting dependencies installation for mRemoteNG project'
    Write-Build Cyan '----------------------------------------------------------------------------------'

    Write-Output '[InstallDeps] Restore nuget dependencies'
    exec { & dotnet restore }
}

task Build {
    <#
    .SYNOPSIS 
    Builds the mRemoteNG project
    #>
    Write-Build Cyan '----------------------------------------------------------------------------------'
    Write-Build Cyan '[Build] Starting the build of mRemoteNG project'
    Write-Build Cyan '----------------------------------------------------------------------------------'

    Write-Output "[Build] Building mRemoteNG"
    if($Rebuild){
        exec { & dotnet msbuild -t:Rebuild -p:Configuration=$BuildConfiguration -nologo -v:$verbosity -m:$parallelism }
    }
    else {
        exec { & dotnet msbuild -t:Build -p:Configuration=$BuildConfiguration -nologo -v:$verbosity -m:$parallelism }
    }

    Write-Output "Build task exit code: $LastExitCode"
    assert($LastExitCode -eq 0) "Build failed"
}

task Test {
    <#
    .SYNOPSIS 
    Runs all available tests and optionally calculates coverage
    #>
    Write-Build Cyan '----------------------------------------------------------------------------------'
    Write-Build Cyan '[Test] Starting the tests on mRemoteNG project'
    Write-Build Cyan '----------------------------------------------------------------------------------'

    if($WithCoverage)
    {
        Write-Output '[Test] Running the mRemoteNG tests and coverage. Does not rebuild the project.'
        exec { & dotnet test --nologo --no-build --no-restore `
                            --configuration:$BuildConfiguration `
                            --logger:"console;verbosity=normal" `
                            --logger:"trx;LogFileName=mremoteng.test.trx" `
                            --results-directory:$REPORTS_DIR `
                            -p:CollectCoverage=true `
                            -p:CoverletOutputFormat="opencover" `
                            -p:CoverletOutput=$(Join-Path $REPORTS_DIR 'mremoteng.cover.xml') `
        }
    }
    else {
        Write-Output '[Test] Running the mRemoteNG tests. Does not rebuild the project.'
        exec { & dotnet test --nologo --no-build --no-restore `
                            --configuration:$BuildConfiguration `
                            --logger:"console;verbosity=normal" `
                            --logger:"trx;LogFileName=mremoteng.test.trx" `
                            --results-directory:$REPORTS_DIR `
        }
    }

    Write-Output "Test task exit code: $LastExitCode"
    assert($LastExitCode -eq 0) "At least one test failed"
}

task CodeQuality {
    <#
    .SYNOPSIS 
    Builds everything, runs the tests and calculates code coverage
    #>
    Write-Build Cyan '----------------------------------------------------------------------------------'
    Write-Build Cyan '[CodeQuality] Starting the code quality analysis on mRemoteNG project'
    Write-Build Cyan '----------------------------------------------------------------------------------'

    Write-Output Orange "[CodeQuality] Code quality analysis not configured. Nothing to do..."
}

task GenerateDocs {
    <#
    .SYNOPSIS
    Generates mRemoteNG documentation.
    #>
    Write-Build Cyan '----------------------------------------------------------------------------------'
    Write-Build Cyan '[GenerateDocs] Generating mRemoteNG documentation'
    Write-Build Cyan '----------------------------------------------------------------------------------'

    Write-Output '[GenerateDocs] Running sphinx to generate mRemoteNG documentation'
    exec { & dotnet build .\mRemoteNGDocumentation\mRemoteNG.Docs.csproj --nologo --configuration:Release }
}

task Stage GenerateDocs, {
    <#
    .SYNOPSIS
    Stages mRemoteNG build files to be further deployed or provided as artifacts by the CI pipeline.
    #>
    Write-Build Cyan '----------------------------------------------------------------------------------'
    Write-Build Cyan '[Stage] Publishing mRemoteNG project'
    Write-Build Cyan '----------------------------------------------------------------------------------'
    
    Write-Output Orange "[Stage] Stage step not configured. Nothing to do..."
}

task Demo {
    Write-Output "[Demo] SemVer stuff" #"\[[v|V](\d+(\.\d+){1,3}) (?:Unreleased)\]"
    $filter = 'rel-\d{1}-\d+'
    Get-SemVer -Filter $filter -Verbose
    Get-SemVerNext -Verbose

    $items = (git tag) 
    @($items | 
        Select-String -Pattern '[0-9]+-' | 
        Sort-Object) + ( $items |
        Select-String -Pattern '[0-9]+-' -NotMatch | 
        Sort-Object) | Select-String -Pattern "^$filter"
}

#####################################
#          Default Task(s)
#####################################
# in-depth cleanup of node modules and other build artifacts
task DeepClean CleanBinObj, Clean

task CleanBuild Clean, Init, Build
task RunTests Build, Test
task CleanPublish Clean, Init, Build, Stage

#region Default Task
task . CleanBuild