# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Functions') -Filter '*.ps1' |
    ForEach-Object { . $_.FullName }

function New-BBServerTestConnection
{
    param(
        $ProjectKey,
        $ProjectName
    )

    $credentialPath = Join-Path -Path $PSScriptRoot -ChildPath '..\.bbservercredential' -Resolve
    if( -not $credentialPath )
    {
        throw ('The credential to a local Bitbucket Server instance does not exist. Please run init.ps1 in the root of the repository to install a local Bitbucket Server. This process creates a credential and saves it in a secure format. The automated tests use this credential to connect to Bitbucket Server when running tests.')
    }
    $credential = Import-Clixml -Path $credentialPath
    if( -not $credential )
    {
        throw ('The credential in ''{0}'' is not valid. Please delete this file, uninstall your local Bitbucket Server instance (with the Uninstall-BitbucketServer.ps1 PowerShell script in the root of the repository), and re-run init.ps1.')
    }
    $conn = New-BBServerConnection -Credential $credential -Uri ('http://{0}:7990' -f $env:COMPUTERNAME.ToLowerInvariant())

    if( $ProjectKey -and $ProjectName )
    {
        New-BBServerProject -Connection $conn -Key $ProjectKey -Name $ProjectName -ErrorAction Ignore | Out-Null
    }

    return $conn
}

function New-TestProjectInfo
{
    $key = ([IO.Path]::GetRandomFileName()) -replace '[^A-Za-z0-9_]','_'
    $key -replace '^\d+',''
    'New-BBServerProject-New-Project-{0}' -f [IO.Path]::GetRandomFileName()
}

Export-ModuleMember -Function '*'