# CloneApp
CloneApp clones the API Permissions of an Azure AD App to the same or another tenant. You export an XML file and import to create a new App.

Can also be imported via a Gist.


## Installation

```powershell
Install-Module AzureAD
Install-Module CloneApp
```


## Syntax

#### `Connect`
```powershell
Connect-AzureAD
```

#### `Export`

```powershell
Export-AzureADApp -Name TestApp -Path C:\temp\
```

#### `Import`

```powershell
$params = @{
    Owner               = 'admin@contoso.onmicrosoft.com'
    XMLPath             = 'C:\temp\TestApp-20200808-0349.xml'
    Name                = 'NewApp'
    SecretDurationYears = 10
    ConsentAction       = 'Both'
}
Import-AzureADApp @params
```

#### `Import from GIST`

```powershell
$params = @{
    Owner               = 'admin@contoso.onmicrosoft.com'
    GithubUsername      = 'kevinblumenfeld'
    GistFilename        = 'testapp.xml'
    Name                = 'NewApp'
    SecretDurationYears = 10
    ConsentAction       = 'Both'
}
Import-AzureADApp @params
```

## Example Usage

![example-usage](https://user-images.githubusercontent.com/28877715/89929651-7d9b4200-dbd7-11ea-808b-144b5a9a77e3.gif)
