function Install-Node
{
    [Whiskey.Task('InstallNode')]
    [Whiskey.RequiresTool('Node', PathParameterName='NodePath')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter
    )

    if( $TaskParameter['Force'] -or $TaskParameter['Version'] )
    {
        #Skips install if specified version is already installed
        Install-WhiskeyNode -InstallRoot $TaskContext.BuildRoot -Version $TaskParameter['Version']
    }
}