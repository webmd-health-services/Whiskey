
function Get-BMApplication
{
    <#
    .SYNOPSIS
    Gets the applications in BuildMaster.
    
    .DESCRIPTION
    Gets the applications in BuildMaster. Uses the BuildMaster native API, which can change without notice between releases. By default, this function returns *all* applications. 
    
    To get a specific application, pass its name with the `Name` parameter. Active and inactive applications are returned. If an application with the name doesn't exist, you'll get nothing back.

    .EXAMPLE
    Get-BMApplication -Session $session

    Demonstrates how to get all the applications in the BuildMaster instance specifie in the `$session` object.

    .EXAMPLE
    Get-BMApplication -Session $session -Name 'MyApplication'

    Demonstrates how to get a specific application. In this case, the application `MyApplication` is returned.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The session to use when connecting to BuildMaster. Use `New-BMSession` to create session objects.
        $Session,

        [string]
        # The name of the application to get. 
        $Name
    )

    Set-StrictMode -Version 'Latest'

    $parameters = @{
                        Application_Count = 0;
                        IncludeInactive_Indicator = $true;
                   } 

    Invoke-BMNativeApiMethod -Session $Session -Name 'Applications_GetApplications' -Parameter $parameters |
        Where-Object { 
            if( $Name )
            {
                return $_.Application_Name -eq $Name
            }
            return $true
        }
}
