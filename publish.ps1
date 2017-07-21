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

[CmdletBinding()]
param(
)

#Requires -Version 4
Set-StrictMode -Version 'Latest'

$moduleRoot = (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey' -Resolve)
$manifest = Test-ModuleManifest -Path (Join-Path -Path $moduleRoot -ChildPath 'Whiskey.psd1' -Resolve)
if( -not $manifest )
{
    return
}

$filesNotReady = git status --porcelain --ignored $moduleRoot
if( $filesNotReady )
{
    Write-Error -Message ('There are uncommitted changes under Whiskey. Please remove these files or commit them.{0}{1}' -f [Environment]::NewLine,($filesNotReady -join [Environment]::NewLine))
    return
}

$privateData = $manifest.PrivateData['PSData']

$nugetKeyPath = Join-Path -Path $PSScriptRoot -ChildPath '.whsgallerykey'
if( -not (Test-Path -Path $nugetKeyPath -PathType Leaf) )
{
    $key = Read-Host -Prompt 'Please enter your ProGet PowerShell API key:' -AsSecureString
    $key | Export-Clixml -Path $nugetKeyPath
}

$key = Import-Clixml -Path $nugetKeyPath
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($key)
$key = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

Publish-Module -Path $moduleRoot -NuGetApiKey $key -Repository 'WhsPowerShell' -ReleaseNotes $privateData['ReleaseNotes'] -ProjectUri $privateData['ProjectUri']
