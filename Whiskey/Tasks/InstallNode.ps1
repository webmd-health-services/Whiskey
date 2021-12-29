function Install-Node
{
    [Whiskey.Task('InstallNode')]
    [Whiskey.RequiresTool('Node', PathParameterName='NodePath')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [String]$Version,

        [switch]$Force
    )

    if( $Force -or $Version )
    {
        # Skips install if specified version is already installed
        Install-WhiskeyNode -InstallRootPath $TaskContext.BuildRoot `
                            -Version $Version `
                            -OutFileRootPath $TaskContext.OutputDirectory
    }
}