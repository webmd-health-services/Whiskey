
function ConvertTo-WhiskeyContext
{
    <#
    .SYNOPSIS
    Converts an `Whiskey.Context` returned by `ConvertFrom-WhiskeyContext` back into a `Whiskey.Context` object.
    
    .DESCRIPTION
    Some tasks need to run in background jobs and need access to Whiskey's context. This function converts an object returned by `ConvertFrom-WhiskeyContext` back into a `Whiskey.Context` object. 

        $serializableContext = $TaskContext | ConvertFrom-WhiskeyContext
        $job = Start-Job {
                    Invoke-Command -ScriptBlock {
                                            $VerbosePreference = 'SilentlyContinue';
                                            # Or wherever your project keeps Whiskey relative to your task definition.
                                            Import-Module -Name (Join-Path -Path $using:PSScriptRoot -ChildPath '..\Whiskey' -Resolve -ErrorAction Stop)
                                        }
                    [Whiskey.Context]$context = $using:serializableContext | ConvertTo-WhiskeyContext 
                    # Run your task
              }

    .EXAMPLE
    $serializedContext | ConvertTo-WhiskeyContext

    Demonstrates how to call `ConvertTo-WhiskeyContext`. See the description for a full example.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline)]
        [object]
        # The context to convert. You can pass an existing context via the pipeline.
        $InputObject
    )

    process 
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        try
        {
            function Sync-ObjectProperty
            {
                param(
                    [Parameter(Mandatory=$true)]
                    [object]
                    $Source,

                    [Parameter(Mandatory=$true)]
                    [object]
                    $Destination,

                    [string[]]
                    $ExcludeProperty
                )

                $destinationType = $Destination.GetType()
                $destinationType.DeclaredProperties |
                    Where-Object { $ExcludeProperty -notcontains $_.Name } |
                    Where-Object { $_.GetSetMethod($false) } |
                    Select-Object -ExpandProperty 'Name' |
                    ForEach-Object { 
                        Write-Debug ('{0}  {1} -> {2}' -f $_,$Destination.$_,$Source.$_)
                                
                        $propertyType = $destinationType.GetProperty($_).PropertyType
                        if( $propertyType.IsSubclassOf([IO.FileSystemInfo]) )
                        {
                            if( $Source.$_ )
                            {
                                Write-Debug -Message ('{0} {1} = {2}' -f $propertyType.FullName,$_,$Source.$_)
                                $Destination.$_ = New-Object $propertyType.FullName -ArgumentList $Source.$_.FullName
                            }
                        }
                        else
                        {
                            $Destination.$_ = $Source.$_ 
                        }
                    }

                Write-Debug ('Source      -eq $null  ?  {0}' -f ($Source -eq $null))
                if( $Source -ne $null )
                {
                    Write-Debug -Message 'Source'
                    Get-Member -InputObject $Source | Out-String | Write-Debug
                }

                Write-Debug ('Destination -eq $null  ?  {0}' -f ($Destination -eq $null))
                if( $Destination -ne $null )
                {
                    Write-Debug -Message 'Destination'
                    Get-Member -InputObject $Destination | Out-String | Write-Debug
                }

                Get-Member -InputObject $Destination -MemberType Property |
                    Where-Object { $ExcludeProperty -notcontains $_.Name } |
                    Where-Object {
                        $name = $_.Name
                        if( -not $name )
                        {
                            return
                        }

                        $value = $Destination.$name
                        if( $value -eq $null )
                        {
                            return
                        }

                        Write-Debug ('Destination.{0,-20} -eq $null  ?  {1}' -f $name,($value -eq $null))
                        Write-Debug ('           .{0,-20} is            {1}' -f $name,$value.GetType())
                        return (Get-Member -InputObject $value -Name 'Keys') -or ($value -is [Collections.IList])
                    } |
                    ForEach-Object {
                        $propertyName = $_.Name
                        Write-Debug -Message ('{0}.{1} -> {2}.{1}' -f $Source.GetType(),$propertyName,$Destination.GetType())
                        $destinationObject = $Destination.$propertyName
                        $sourceObject = $source.$propertyName
                        if( (Get-Member -InputObject $destinationObject -Name 'Keys') )
                        {
                            $keys = $sourceObject.Keys
                            foreach( $key in $keys )
                            {
                                $value = $sourceObject[$key]
                                Write-Debug ('    [{0,-20}] -> {1}' -f $key,$value)
                                $destinationObject[$key] = $sourceObject[$key]
                            }
                        }
                        elseif( $destinationObject -is [Collections.IList] )
                        {
                            $idx = 0
                            foreach( $item in $sourceObject )
                            {
                                Write-Debug('    [{0}] {1}' -f $idx++,$item)
                                $destinationObject.Add($item)
                            }
                        }
                    }
            }

            $buildInfo = New-WhiskeyBuildMetadataObject
            Sync-ObjectProperty -Source $InputObject.BuildMetadata -Destination $buildInfo -Exclude @( 'BuildServer' )
            if( $InputObject.BuildMetadata.BuildServer )
            {
                $buildInfo.BuildServer = $InputObject.BuildMetadata.BuildServer
            }

            $buildVersion = New-WhiskeyVersionObject
            Sync-ObjectProperty -Source $InputObject.Version -Destination $buildVersion -ExcludeProperty @( 'SemVer1', 'SemVer2', 'SemVer2NoBuildMetadata' )
            if( $InputObject.Version )
            {
                if( $InputObject.Version.SemVer1 )
                {
                    $buildVersion.SemVer1 = $InputObject.Version.SemVer1.ToString()
                }

                if( $InputObject.Version.SemVer2 )
                {
                    $buildVersion.SemVer2 = $InputObject.Version.SemVer2.ToString()
                }

                if( $InputObject.Version.SemVer2NoBuildMetadata )
                {
                    $buildVersion.SemVer2NoBuildMetadata = $InputObject.Version.SemVer2NoBuildMetadata.ToString()
                }
            }

            [Whiskey.Context]$context = New-WhiskeyContextObject
            Sync-ObjectProperty -Source $InputObject -Destination $context -ExcludeProperty @( 'BuildMetadata', 'Configuration', 'Version', 'Credentials', 'TaskPaths', 'ApiKeys' )
            if( $context.ConfigurationPath )
            {
                $context.Configuration = Import-WhiskeyYaml -Path $context.ConfigurationPath
            }

            $context.BuildMetadata = $buildInfo
            $context.Version = $buildVersion

            foreach( $credentialID in $InputObject.Credentials.Keys )
            {
                $serializedCredential = $InputObject.Credentials[$credentialID]
                $username = $serializedCredential.UserName
                $password = ConvertTo-SecureString -String $serializedCredential.Password -Key $InputObject.CredentialKey
                [pscredential]$credential = New-Object 'pscredential' $username,$password
                Add-WhiskeyCredential -Context $context -ID $credentialID -Credential $credential
            }

            foreach( $apiKeyID in $InputObject.ApiKeys.Keys )
            {
                $serializedApiKey = $InputObject.ApiKeys[$apiKeyID]
                $apiKey = ConvertTo-SecureString -String $serializedApiKey -Key $InputObject.CredentialKey
                Add-WhiskeyApiKey -Context $context -ID $apiKeyID -Value $apiKey
            }

            foreach( $path in $InputObject.TaskPaths )
            {
                $context.TaskPaths.Add((New-Object -TypeName 'IO.FileInfo' -ArgumentList $path))
            }

            Write-Debug 'Variables'
            $context.Variables | ConvertTo-Json -Depth 50 | Write-Debug
            Write-Debug 'ApiKeys'
            $context.ApiKeys | ConvertTo-Json -Depth 50 | Write-Debug
            Write-Debug 'Credentials'
            $context.Credentials | ConvertTo-Json -Depth 50 | Write-Debug
            Write-Debug 'TaskDefaults'
            $context.TaskDefaults | ConvertTo-Json -Depth 50 | Write-Debug
            Write-Debug 'TaskPaths'
            $context.TaskPaths | ConvertTo-Json | Write-Debug

            return $context
        }
        finally
        {
            # Don't leave the decryption key lying around.
            [Array]::Clear($InputObject.CredentialKey,0,$InputObject.CredentialKey.Length)
        }
    }
}