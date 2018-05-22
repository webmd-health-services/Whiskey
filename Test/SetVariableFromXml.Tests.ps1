
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$path = $null
[Whiskey.Context]$context = $null

function GivenXmlFile
{
    param(
        $Path,
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath $Path)
    $script:path = $Path
}

function GivenWhiskeyYml
{
    param(
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml')
}

function Init
{
    $script:path = $null
    $script:context = $null
}

function ThenNoErrors
{
    It ('should not write any errors') {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function ThenVariable
{
    param(
        $Name,
        $Is
    )

    It ('should create variable') {
        $context.Variables.ContainsKey($Name) | Should -Be $true
        $context.Variables[$Name] -join ',' | Should -Be ($Is -join ',')
    }
}

function WhenRunningTask
{
    $Global:Error.Clear()

    [Whiskey.Context]$context = New-WhiskeyTestContext -ForDeveloper -ConfigurationPath (Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml')
    $parameter = $context.Configuration['Build'] | Where-Object { $_.ContainsKey('SetVariableFromXml') } | ForEach-Object { $_['SetVariableFromXml'] }
    Invoke-WhiskeyTask -TaskContext $context -Name 'SetVariableFromXml' -Parameter $parameter
    $script:context = $context
}

Describe 'SetVariableFromXml.when reading single element' {
    Init
    GivenXmlFile 'fubar.xml' @'
<root>
    <element1>one</element1>
    <element2>two</element2>
</root>
'@
    GivenWhiskeyYml @'
Build:
- SetVariableFromXml:
    Path: fubar.xml
    Variables:
        Var1: /root/element1
'@
    WhenRunningTask
    ThenVariable 'Var1' -Is 'one'
}

Describe 'SetVariableFromXml.when reading multiple elements' {
    Init
    GivenXmlFile 'fubar.xml' @'
<root>
    <element>one</element>
    <element>two</element>
</root>
'@
    GivenWhiskeyYml @'
Build:
- SetVariableFromXml:
    Path: fubar.xml
    Variables:
        Var1: /root/element
'@
    WhenRunningTask
    ThenVariable 'Var1' -Is @('one','two')
}

Describe 'SetVariableFromXml.when reading attribute' {
    Init
    GivenXmlFile 'fubar.xml' @'
<root>
    <element1 attr="one" />
    <element2 attr="two" />
</root>
'@
    GivenWhiskeyYml @'
Build:
- SetVariableFromXml:
    Path: fubar.xml
    Variables:
        Var1: /root/element1/@attr
'@
    WhenRunningTask
    ThenVariable 'Var1' -Is 'one'
}

Describe 'SetVariableFromXml.when reading multiple attributes' {
    Init
    GivenXmlFile 'fubar.xml' @'
<root>
    <element attr="one" />
    <element attr="two" />
</root>
'@
    GivenWhiskeyYml @'
Build:
- SetVariableFromXml:
    Path: fubar.xml
    Variables:
        Var1: /root/element/@attr
'@
    WhenRunningTask
    ThenVariable 'Var1' -Is @('one','two')
}

Describe 'SetVariableFromXml.when no element' {
    Init
    GivenXmlFile 'fubar.xml' @'
<root>
    <element attr="one" />
</root>
'@
    GivenWhiskeyYml @'
Build:
- SetVariableFromXml:
    Path: fubar.xml
    Variables:
        Var1: /root/element/fubar
'@
    WhenRunningTask
    ThenVariable 'Var1' -Is ''
    ThenNoErrors
}

Describe 'SetVariableFromXml.when XML has namespaces' {
    Init
    GivenXmlFile 'fubar.xml' @'
<root xmlns="http://example.com/">
    <element>one</element>
</root>
'@
    GivenWhiskeyYml @'
Build:
- SetVariableFromXml:
    Path: fubar.xml
    NamespacePrefixes:
        ex: http://example.com/
    Variables:
        Var1: /ex:root/ex:element
'@
    WhenRunningTask
    ThenVariable 'Var1' -Is 'one'
    ThenNoErrors
}


Describe 'SetVariableFromXml.when selecting values from an MSBuild .csproj file' {
    Init
    GivenXmlFile 'fubar.csproj' @'
<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
  <PropertyGroup>
    <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>
    <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>
    <ProjectGuid>{023659A0-0632-4B73-8901-BD95988748D7}</ProjectGuid>
    <OutputType>Library</OutputType>
    <AppDesignerFolder>Properties</AppDesignerFolder>
    <RootNamespace>Whiskey</RootNamespace>
    <AssemblyName>Whiskey</AssemblyName>
    <TargetFrameworkVersion>v4.6.1</TargetFrameworkVersion>
    <FileAlignment>512</FileAlignment>
    <TargetFrameworkProfile />
  </PropertyGroup>
  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">
    <DebugSymbols>true</DebugSymbols>
    <DebugType>full</DebugType>
    <Optimize>false</Optimize>
    <OutputPath>bin\Debug\</OutputPath>
    <DefineConstants>DEBUG;TRACE</DefineConstants>
    <ErrorReport>prompt</ErrorReport>
    <WarningLevel>4</WarningLevel>
  </PropertyGroup>
  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Release|AnyCPU' ">
    <DebugType>pdbonly</DebugType>
    <Optimize>true</Optimize>
    <OutputPath>bin\Release\</OutputPath>
    <DefineConstants>TRACE</DefineConstants>
    <ErrorReport>prompt</ErrorReport>
    <WarningLevel>4</WarningLevel>
  </PropertyGroup>
</Project>
'@
    GivenWhiskeyYml @'
Build:
- SetVariableFromXml:
    Path: fubar.csproj
    NamespacePrefixes:
        msb: http://schemas.microsoft.com/developer/msbuild/2003
    Variables:
        OutputPath: "/msb:Project/msb:PropertyGroup[@Condition = \" '$$(Configuration)|$$(Platform)' == '$(WHISKEY_MSBUILD_CONFIGURATION)|AnyCPU' \"]/msb:OutputPath"
'@
    WhenRunningTask
    ThenVariable 'OutputPath' -Is 'bin\Debug\'
    ThenNoErrors
}
