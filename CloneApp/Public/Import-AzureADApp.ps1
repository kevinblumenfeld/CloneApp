function Import-AzureADApp {
    <#
    .SYNOPSIS
    Import Azure AD App name & API permissions from filesystem-based or GIST-based xml

    .DESCRIPTION
    Import Azure AD App name & API permissions from filesystem-based or GIST-based xml

    .PARAMETER Owner
    The owner of the application. For convenience, should be the owner
    that can grant admin consent of the requested API permissions

    .PARAMETER xmlPath
    Filesystem path to the xml created by Export-AzureAD
    Choose this or the Github paramters to grab the xml from a GIST

    .PARAMETER GithubUsername
    Github username where the GIST you wish to import lives

    .PARAMETER GistFilename
    filename of GIST, example: Test.xml
    This is the most recently created file named, Test.xml, for example.
    If there is more than one filename bypassed

    .PARAMETER SecretDurationYears
    Specify how many years the secret should live.
    If you dont use this parameter, no secret will be created

    .PARAMETER Name
    Name of the App to create in the target AzureAD tenant.
    If left blank, will use source tenant app name (plus timestamp of export)

    .PARAMETER ConsentAction
    Valid choices are OpenBrowser, OutputUrl, or Both

    Used to "grant admin consent" for the APIs via URL.
    1. Either the URL is provided via PowerShell console (can be copy/pasted into a browser)
    2. The URL is opened in the default browser
    3. or both

    Alternatively, and admin can simply login to the Azure portal then select the following:

    Azure AD > App Registrations > find/click the App > API permissions > Grant Admin Consent for Tenant

    .EXAMPLE
    Import-AzureADApp -Owner admin@contoso.onmicrosoft.com -GithubUsername kevinblumenfeld `
                      -GistFilename testapp.xml -Name NewApp09 -SecretDurationYears 1 -ConsentAction Both

    .EXAMPLE
    Import-AzureADApp -Owner admin@contoso.onmicrosoft.com `
                      -xmlPath C:\Scripts\TestApp-20200808-0349.xml
                      -Name NewApp01 -SecretDurationYears 1 -ConsentAction OutputUrl

    .NOTES
    If SecretDurationYears is choosen the Secret will be included with the object this function produces

    Example:

    DisplayName   : AppTwo
    ApplicationId : e8f3a6cb-f3c1-4a7d-8cb2-6a72d99816fa
    TenantId      : a334d325-ce6e-49be-bea1-b2058b125a8e
    ObjectId      : b559ab26-31bf-4462-97e4-afc80dbb51e5
    Owner         : demo@contoso.onmicrosoft.com
    Secret        : kHOPOoOWL++Jir0yiYD3SN7bcIoYzvS+XeQJjju/Ef4=


    #>

    [cmdletbinding(DefaultParameterSetName = 'PlaceHolder')]
    param (

        [Parameter(Mandatory, ParameterSetName = 'FileSystem')]
        [Parameter(Mandatory, ParameterSetName = 'GIST')]
        [mailaddress]
        $Owner,

        [Parameter(Mandatory, ParameterSetName = 'FileSystem')]
        [string]
        [ValidateScript( { Test-Path $_ })]
        $xmlPath,

        [Parameter(Mandatory, ParameterSetName = 'GIST')]
        [string]
        $GithubUsername,

        [Parameter(Mandatory, ParameterSetName = 'GIST')]
        [string]
        $GistFilename,

        [Parameter(ParameterSetName = 'FileSystem')]
        [Parameter(ParameterSetName = 'GIST')]
        $SecretDurationYears,

        [Parameter(Mandatory, ParameterSetName = 'FileSystem')]
        [Parameter(Mandatory, ParameterSetName = 'GIST')]
        [string]
        $Name,

        [Parameter(ParameterSetName = 'FileSystem')]
        [Parameter(ParameterSetName = 'GIST')]
        [ValidateSet('OpenBrowser', 'OutputUrl', 'Both')]
        [string]
        $ConsentAction
    )
    $NewAppSplat = @{ }
    if ($ConsentAction) {
        Write-Host 'Consent via Browser/URL requires adding the ReplyUrl, https://portal.azure.com to the new app' -ForegroundColor Cyan
        do {
            $Agree = Read-Host 'Okay to add https://portal.azure.com as a ReplyUrl? (Y/N)'
        } until ($Agree -match 'Y|N')
        if ($Agree -eq 'N') { continue }
        $NewAppSplat['ReplyUrls'] = 'https://portal.azure.com'
    }
    Write-Host "Owner: $Owner" -ForegroundColor Cyan -NoNewline
    try {
        $AppOwner = Get-AzureADUser -ObjectId $Owner -ErrorAction Stop
        Write-Host " Found" -ForegroundColor Green
    }
    catch {
        Write-Host " Not Found. Halting script" -ForegroundColor Red
        continue
    }
    try {
        $null = Get-AzureADApplication -filter "DisplayName eq '$Name'" -ErrorAction Stop
    }
    catch {
        Write-Host "Azure AD Application Name: $Name already exists" -ForegroundColor Red
        Write-Host "Choose a new name with the -Name parameter" -ForegroundColor Cyan
        continue
    }

    if ($PSCmdlet.ParameterSetName -eq 'FileSystem') { $App = Import-Clixml $xmlPath }
    else {
        try {
            $Tempfilepath = Join-Path -Path $Env:TEMP -ChildPath ('{0}.xml' -f [guid]::newguid().guid)
            (Get-CloneGist -Username $GithubUserName -Filename $GistFilename)[0].content | Set-Content -Path $Tempfilepath -ErrorAction Stop
            $App = Import-Clixml $Tempfilepath
        }
        catch {
            Write-Host "Error importing GIST $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
        finally {
            Remove-Item -Path $Tempfilepath -Force -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    $Tenant = Get-AzureADTenantDetail
    try {
        $NewAppSplat['DisplayName'] = $Name
        $NewAppSplat['ErrorAction'] = 'Stop'
        $TargetApp = New-AzureADApplication @NewAppSplat
    }
    catch {
        Write-Host "Unable to create new application:  $($_.Exception.Message)" -ForegroundColor Red
        continue
    }

    $Output = [ordered]@{ }
    $Output['DisplayName'] = $Name
    $Output['ApplicationId'] = $TargetApp.AppId
    $Output['TenantId'] = $Tenant.ObjectID
    $Output['ObjectId'] = $TargetApp.ObjectId
    $Output['Owner'] = $Owner

    $RequiredList = [System.Collections.Generic.List[Microsoft.Open.AzureAD.Model.RequiredResourceAccess]]::new()
    foreach ($ResourceAppId in $App['API'].keys) {
        $RequiredObject = [Microsoft.Open.AzureAD.Model.RequiredResourceAccess]::new()
        $AccessObject = [System.Collections.Generic.List[Microsoft.Open.AzureAD.Model.ResourceAccess]]::new()
        foreach ($ResourceAccess in $App['API'][$ResourceAppId]['ResourceList']) {
            $AccessObject.Add([Microsoft.Open.AzureAD.Model.ResourceAccess]@{
                    Id   = $ResourceAccess.Id
                    Type = $ResourceAccess.Type
                })
        }
        $RequiredObject.ResourceAppId = $ResourceAppId
        $RequiredObject.ResourceAccess = $AccessObject
        $RequiredList.Add($RequiredObject)
    }
    Set-AzureADApplication -ObjectId $TargetApp.ObjectId -RequiredResourceAccess $RequiredList
    Add-AzureADApplicationOwner -ObjectId $TargetApp.ObjectId -RefObjectId $AppOwner.ObjectId

    if ($SecretDurationYears) {
        $Date = Get-Date
        $Params = @{
            ObjectId            = $TargetApp.ObjectId
            EndDate             = $Date.AddYears($SecretDurationYears)
            CustomKeyIdentifier = $Date.ToString("yyyyMMdd_HHmmss")
        }
        $SecretResult = New-AzureADApplicationPasswordCredential @Params
        $Output['Secret'] = $SecretResult.value
    }

    if ($ConsentAction -match 'OutputUrl|Both') {
        Write-Host "Grant Admin Consent by logging in as $Owner here:`r`n" -ForegroundColor Cyan
        $ConsentURL = 'https://login.microsoftonline.com/{0}/v2.0/adminconsent?client_id={1}&state=12345&redirect_uri={2}&scope={3}&prompt=admin_consent' -f @(
            $Tenant.ObjectID, $TargetApp.AppId, 'https://portal.azure.com/', 'https://graph.microsoft.com/.default')

        Write-Host "$ConsentURL" -ForegroundColor Green
    }
    [PSCustomObject]$Output

    if ($ConsentAction -match 'OpenBrowser|Both') { Start-Process $ConsentURL }
}
