
function Resolve-WhiskeyRelativePath
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [String] $Path
    )

    process
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        $realPath = Resolve-Path -Path $Path -ErrorAction Ignore | Select-Object -ExpandProperty 'ProviderPath'
        if( $realPath )
        {
            $Path = $realPath
        }

        $buildRoot = (Get-Location).Path
        $Context = Get-WhiskeyContext
        if( $Context )
        {
            $buildRoot = $Context.BuildRoot.FullName
        }

        $ignoreCase = $IsWindows

        $buildRoot = $buildRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $buildRoot = "$($buildRoot)$([IO.Path]::DirectorySeparatorChar)"
        if( $Path.StartsWith($buildRoot, $ignoreCase, [cultureinfo]::CurrentCulture) )
        {
            $Path = $Path.Substring(($buildRoot.Length - 1))
            $Path = ".$($Path)"
        }

        return $Path
    }
}
