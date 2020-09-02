function Install-Node
{
    [Whiskey.Task('InstallNode')]
    [Whiskey.RequiresTool('Node', PathParameterName='NodePath')]
    [CmdletBinding()]
    param(
    )
}