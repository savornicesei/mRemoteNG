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

.PARAMETER FailBuildWhenTestsFail
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
    [switch] $WithCoverage = $false,

    [Parameter(HelpMessage = 'Fail the build if at least one test failed')]
    [switch] $FailBuildWhenTestsFail = $false
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

# load first own script related to powershell and powershell modules
. "$(Join-Path $PSScriptRoot 'scripts' 'pwsh_functions.ps1')"
#load additional modules
Set-PSModules -Modules jit-semver -AllowPrerelease
#load own build-related powershell scripts
. "$(Join-Path $PSScriptRoot 'scripts' 'dotnet_framework_functions.ps1')"

#####################################################
#         initialization: global variables
#####################################################
# is CI build on Appveyor
$IS_CI_APPVEYOR = $null -ne $env:APPVEYOR
# is CI build on GitHub
$IS_CI_GITHUB = $true -eq $env:GITHUB_ACTIONS
# is CI build, either on Appveyor or on GitHub
$IS_CI_BUILD = $IS_CI_APPVEYOR -or $IS_CI_GITHUB

$SRC_DIR = Join-Path $BuildRoot 'src'
$TESTS_DIR = Join-Path $BuildRoot 'tests'
$INSTALLER_DIR = Join-Path $BuildRoot 'installer'
$DOCS_DIR = Join-Path $BuildRoot 'documentation'
$TOOLS_DIR = Join-Path $BuildRoot 'Tools'
$REPORTS_DIR = Join-Path $BuildRoot 'reports'

$MSBUILD = Get-MsBuild -ToolsDir $TOOLS_DIR
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

    Src directory: $SRC_DIR,
    Tests directory: $TESTS_DIR,
    Installer directory: $INSTALLER_DIR,
    Documentation directory: $DOCS_DIR,
    Tools directory: $TOOLS_DIR,
    Reports directory: $REPORTS_DIR,
    
    msbuild.exe path: $MSBUILD"
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
        Write-Output '[Init] Creating reports directory...'
        New-Item -Path $REPORTS_DIR -Type Directory -Force | Out-Null
    }

    Write-Output '[Init] Installing dotnet tools'
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
        Write-Output -Message '[Clean] Cleaning reports directory...'
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
    Write-Build Cyan '[InstallDeps] Starting dependencies installation for mRemoteNG project'
    Write-Build Cyan '----------------------------------------------------------------------------------'

    Write-Output '[InstallDeps] Restore nuget dependencies'
    exec { & dotnet restore }
}

task InstallCert -If ($BuildConfiguration -like 'Release*'){
     <#
    .SYNOPSIS
    Decrypts and installs mRemoteNG signing certificate in Certificate Store if building in Release mode.
    #>
    Write-Build Cyan '----------------------------------------------------------------------------------'
    Write-Build Cyan '[InstallCert] Starting certificate decrypt and installation for mRemoteNG project'
    Write-Build Cyan '----------------------------------------------------------------------------------'

    Write-Output '[InstallCert] Decrypt certificate'

    Write-Output '[InstallCert] Load certificate in certificate store'
}

task Build {
    <#
    .SYNOPSIS 
    Builds the mRemoteNG project
    #>
    Write-Build Cyan '----------------------------------------------------------------------------------'
    Write-Build Cyan '[Build] Starting the build of mRemoteNG project'
    Write-Build Cyan '----------------------------------------------------------------------------------'

    Write-Output '[Build] Building mRemoteNG'
    if($Rebuild){
        exec { & $MSBUILD -t:Rebuild -p:Configuration=$BuildConfiguration -nologo -v:$verbosity -m:$parallelism }
    }
    else {
        exec { & $MSBUILD -t:Build -p:Configuration=$BuildConfiguration -nologo -v:$verbosity -m:$parallelism }
    }

    Write-Output "Build task exit code: $LastExitCode"
    assert($LastExitCode -eq 0) 'Build failed'
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
                            --collect:"XPlat Code Coverage" `
                            --settings $(Join-Path $BuildRoot 'tests' 'coverlet.runsettings') `
                            --verbosity detailed ` #q[uiet], m[inimal], n[ormal], d[etailed], diag[nostic]
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
    if($FailBuildWhenTestsFail){
        assert($LastExitCode -eq 0) 'At least one test failed'
    }
    else{
        return 0
    }
}

task CodeQuality {
    <#
    .SYNOPSIS 
    Builds everything, runs the tests and calculates code coverage
    #>
    Write-Build Cyan '----------------------------------------------------------------------------------'
    Write-Build Cyan '[CodeQuality] Starting the code quality analysis on mRemoteNG project'
    Write-Build Cyan '----------------------------------------------------------------------------------'

    Write-Output Orange '[CodeQuality] Code quality analysis for SonarQube'
    exec { dotnet reportgenerator `
        -reports:$(Join-Path $REPORTS_DIR '**' 'coverage.cobertura.xml') `
        -targetdir:$REPORTS_DIR `
        -reporttypes:Html;SonarQube `
        -sourcedirs:$SRC_DIR `
        -title:mRemoteNG `
        -tag:1.77.1 `
    }
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
    exec { & dotnet build $(Join-Path $DOCS_DIR 'mRemoteNG.Docs.csproj') --nologo --configuration:Release }
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
task RunCodeQuality CleanBuild, Test, CodeQuality
task CleanPublish Clean, Init, Build, Stage

#region Default Task
task . CleanBuild