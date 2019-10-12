
$dirInfo = Get-Item -Path $PSScriptRoot

#Start-Job {

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
                                        $value = New-Object $propertyType.FullName -ArgumentList $Source.$_.FullName
                                        $Destination.$_ = $value
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
                    
                    
                    
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey')

    $context = New-Object 'Whiskey.Context'

    [IO.DirectoryInfo]$dir = New-Object 'io.directoryinfo' $dirInfo.FullName
    $context.'OutputDirectory' = $dir
    $context.OutputDirectory

    $newContext = New-Object 'Whiskey.Context'

    Sync-ObjectProperty -Source $context -Destination $newContext

#} | Wait-Job | Receive-Job