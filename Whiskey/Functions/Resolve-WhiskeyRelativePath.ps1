
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

        if( -not [IO.Path]::IsPathRooted($Path) )
        {
            $context = Get-WhiskeyContext
            $Path = Join-Path -Path $Context.BuildRoot.FullName -ChildPath $Path
        }

        $currentDir = (Get-Location).Path
        $currentDir = $currentDir.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $currentDir = "$($currentDir)$([IO.Path]::DirectorySeparatorChar)"

        $ignoreCase = $IsWindows

        if( $Path.StartsWith($currentDir, $ignoreCase, [cultureinfo]::CurrentCulture) )
        {
            $Path = ".$($Path.Substring(($currentDir.Length - 1)))"
        }

        return $Path
    }
}
