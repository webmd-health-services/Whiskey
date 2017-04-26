
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
    
        [Switch]
        # Use 32-bit MSBuild
        $Use32Bit,

        [string[]]
        # Extra arguments to pass to MSBuild.
        $ArgumentList = @()
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
    Write-Verbose "    Found MSBuild at '$pathToMSBuild'."

    if( $Target )
    {
        $ArgumentList += "/t:{0}" -f ($Target -join ';')
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
            $ArgumentList += "/p:$name=""{0}""" -f ($value -replace ' ','%20')
        }
    }

    if( $pscmdlet.ShouldProcess($Path, $ArgumentList) )
    {
        & $pathToMSBuild $ArgumentList /nologo $Path
        if( $LASTEXITCODE -ne 0 )
        {
            Write-Error ("MSBuild exited with code {0}." -f $LASTEXITCODE)
        }
    }
}