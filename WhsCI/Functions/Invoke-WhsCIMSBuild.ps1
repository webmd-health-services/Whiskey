
# Private function pulled from WhsAutomation module in Arc repository.
function Invoke-WhsCIMSBuild
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Position=0,Mandatory=$true)]
        [Alias('ProjectFile')]
        [string]
        # The project file to run.
        $Path,
    
        [Parameter(Position=1,Mandatory=$false)]
        [Alias('Targets')]
        [string[]]
        # The targets to run.  Seperate multipe targets by commas.
        $Target,
    
        [Parameter(Mandatory=$false)]
        [Alias('Properties')]
        [string[]]
        # The properties to pass.  Seperate multiple name=value pairs with commas.
        $Property = @(),
    
        [Parameter(Mandatory=$false)]
	    [ValidateSet("q", "m", "n", "d", "diag")]
        [string]
        # The logging verbosity.  One of 'q', 'm', 'n', 'd', or 'diag'.
        $Verbosity,
    
        [Parameter(Mandatory=$false)]
        [Switch]
        # If set, saves detailed output to msbuild.log in the current directory.
        $FileLogger,
    
        [Parameter()]
        [string]
        # The path to a file where logging output should be saved in XML format.
        $XmlLogPath,
    
        [Parameter(Mandatory=$false)]
        [Switch]
        # If set, enables multi-CPU builds.
        $MaxCPU,
    
        [Switch]
        # Use 32-bit MSBuild
        $Use32Bit,

        [Switch]
        # Return an object representing the result of the build.
        $PassThru
    )

    #Requires -Version 3
    Set-StrictMode -Version 'Latest'

    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $pathToMSBuild = "${env:ProgramFiles(x86)}\MSBuild\12.0\bin\amd64\MSBuild.exe"
    if( -not (Test-Path $pathToMSBuild) )
    {
        $pathToMSBuild = "${env:SystemRoot}\Microsoft.Net\Framework64\v4.0.30319\MSBuild.exe"
    }
    if( $Use32Bit -or -not (Test-Path $pathToMSBuild) )
    {
        $pathToMSBuild = "${env:ProgramFiles(x86)}\MSBuild\12.0\bin\MSBuild.exe"
        if( -not (Test-Path $pathToMSBuild) )
        {
            $pathToMSBuild = "${env:SystemRoot}\Microsoft.Net\Framework\v4.0.30319\MSBuild.exe"
        }
    }

    if( -not (Test-path $pathToMSBuild) )
    {
        Write-Error "Unable to find MSBuild.  Has it been installed?"
        return
    }
    Write-Verbose "Using MSBuild at '$pathToMSBuild'."

    $msbuildArgs = @()

    if( $Target )
    {
        $msbuildArgs += "/t:{0}" -f ($Target -join ';')
    }

    if( $Property )
    {
        foreach( $item in $Property )
        {
            $name,$value = $item -split '=',2
            $value = $value.Trim('"')
            $value = $value.Trim("'")
            if( $value.EndsWith( '\' ) )
            {
                $value += '\'
            }
            $msbuildArgs += "/p:$name=""{0}""" -f ($value -replace ' ','%20')
        }
    }

    if( $Verbosity )
    {
        $msbuildArgs += "/v:$Verbosity"
    }

    if( $FileLogger )
    {
        $msbuildArgs += '/flp:v=d'
    }

    if( $MaxCPU )
    {
        $msbuildArgs += '/maxcpucount'
    }

    if( $XmlLogPath )
    {
        $xmlLogDir = Split-Path -Parent $xmlLogPath
        if( -not (Test-Path $xmlLogDir -PathType Container) )
        {
            $null = New-Item $xmlLogDir -ItemType Directory -Force
        }
        $ccnetXmlLogger = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\ThoughtWorks.CruiseControl.MSBuild.dll' -Resolve
        $msbuildArgs += """/l:$ccnetXmlLogger;$XmlLogPath"""
    }

    $result = [pscustomobject] @{
                                    ExitCode = 0; 
                                    Output = @();
                                }
    if( $pscmdlet.ShouldProcess($Path, $msbuildArgs) )
    {
        $writeHostParams = @{ }
        $output = New-Object 'Collections.Generic.List[string]' 
        & $pathToMSBuild @msbuildArgs /nologo $Path | 
            ForEach-Object { 
                if( $PassThru )
                {
                    [void] $output.Add( $_ ) 
                }
                else
                {
                    $writeHostParams.Clear()
                    if( $_ -match '((\(\d+,\d+\): )?(error|warning) ((.*?)\d+)?: .*)$' )
                    {
                        if( $Matches[3] -eq 'error' )
                        {
                            $writeHostParams.ForegroundColor = 'Red'
                        }
                        elseif( $Matches[3] -eq 'warning' )
                        {
                            $writeHostParams.ForegroundColor = 'Yellow'
                        }
                    }
                    Write-Host -Object $_ @writeHostParams
                }
            }

        $result.ExitCode = $LastExitCode
        $result.Output = $output.ToArray()
        if( $PassThru )
        {
            return $result
        }
        if( $result.ExitCode -ne 0 )
        {
            Write-Error ("MSBuild exited with code {0}." -f $result.ExitCode)
        }
    }
}