function Import-TemplateApp {

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
    $Date = Get-Date
    $NewAppSplat = @{ }
    $NewAppSplat['ReplyUrls'] = 'https://portal.azure.com'
    $Name = '{0}-{1}' -f $Name, $Date.ToString("yyyyMMdd_HHmmss")
    Write-Host "Finding ObjectId for owner: $Owner" -ForegroundColor Cyan -NoNewline
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
        $Params = @{
            ObjectId            = $TargetApp.ObjectId
            EndDate             = $Date.AddYears($SecretDurationYears)
            CustomKeyIdentifier = $Date.ToString("yyyyMMdd_HHmmss")
        }
        $SecretResult = New-AzureADApplicationPasswordCredential @Params
        $Output['Secret'] = $SecretResult.value
    }

    if ($ConsentAction -match 'OutputUrl|Both') {
        Write-Host "Grant Admin Consent by logging in as $($Owner.Address) here:`r`n" -ForegroundColor Cyan
        $ConsentURL = 'https://login.microsoftonline.com/{0}/v2.0/adminconsent?client_id={1}&state=12345&redirect_uri={2}&scope={3}&prompt=admin_consent' -f @(
            $Tenant.ObjectID, $TargetApp.AppId, 'https://portal.azure.com/', 'https://graph.microsoft.com/.default')

        Write-Host "$ConsentURL" -ForegroundColor Green
    }
    [PSCustomObject]$Output

    if ($ConsentAction -match 'OpenBrowser|Both') {
        Write-Host "Opening your browser now. Once open, sign in with the same Global Admin that you just used to login to Azure AD" -ForegroundColor Cyan
        Write-Host "Once open, sign in with the same Global Admin that you just used to login to Azure AD" -ForegroundColor Cyan
        Start-Process $ConsentURL
    }
}
