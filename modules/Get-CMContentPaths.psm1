function Get-CMApplicationContentPaths {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the Primary Site server")]
        [ValidateNotNullOrEmpty()]
        [string]$SiteServer,

        [Parameter(Mandatory = $true)]
        [string]
        $SiteCode
    )
    begin {
        try {
            Add-Type -Path (Join-Path -Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName -ChildPath "Microsoft.ConfigurationManagement.ApplicationManagement.dll") -ErrorAction Stop
            Add-Type -Path (Join-Path -Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName -ChildPath "Microsoft.ConfigurationManagement.ApplicationManagement.Extender.dll") -ErrorAction Stop
            Add-Type -Path (Join-Path -Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName -ChildPath "Microsoft.ConfigurationManagement.ApplicationManagement.MsiInstaller.dll") -ErrorAction Stop
        }
        catch [System.UnauthorizedAccessException] {
            Write-OutputBox -OutputBoxMessage "Access denied when attempting to load ApplicationManagement dll's" -Type ERROR ; break
        }
        catch [System.Exception] {
            Write-OutputBox -OutputBoxMessage "Unable to load required ApplicationManagement dll's. Make sure that you're running this tool on system where the ConfigMgr console is installed and that you're running the tool elevated" -Type ERROR ; break
        }
    }
    process {
        $counter = 0
        $AppList = @()
        $Applications = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class "SMS_ApplicationLatest" -ComputerName $SiteServer
        $ApplicationsCount = $Applications.Count
        foreach ($Application in $Applications) {
            Write-Progress -Activity "Getting Applicaiton Info" -Status "$($Application.LocalizedDisplayName)" -PercentComplete ((++$counter / $ApplicationsCount) * 100)
            if ($Application.IsExpired) {continue} #Skip retired applications
            $AppInfo = New-Object -TypeName PSObject
            $AppInfo | Add-Member -MemberType NoteProperty -Name "Name" -Value $Application.LocalizedDisplayName
            $AppInfo | Add-Member -MemberType NoteProperty -Name "Id" -Value $Application.CI_UniqueID
            $AppInfo | Add-Member -MemberType NoteProperty -Name "DeploymentTypes" -Value (New-Object System.Collections.ArrayList)
            if ($Application.HasContent -eq $true) {
                $Application.Get() # Get Application object including Lazy properties
                $AppInfo | Add-Member -MemberType NoteProperty -Name "XML" -Value ([Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::DeserializeFromString($Application.SDMPackageXML, $true))
                foreach ($DeploymentType in $AppInfo.XML.DeploymentTypes) {
                    $DepType = New-Object -TypeName psobject
                    $DepType | Add-Member -MemberType NoteProperty -Name "Name" -Value $DeploymentType.Title
                    $DepType | Add-Member -MemberType NoteProperty -Name "ContentPaths" -Value (New-Object System.Collections.ArrayList)
                    foreach($loc in $DeploymentType.Installer.Contents) {
                        $DepType.ContentPaths.Add($loc.Location) | Out-Null
                    }
                    $AppInfo.DeploymentTypes.Add($DepType) | Out-Null
                }
            } else { 
                continue
            }
            $AppList += $AppInfo
        }
        Write-Progress -Activity "Done" -Completed
        return $AppList
    }
}

function Get-CMPackageContentPaths {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the Primary Site server")]
        [ValidateNotNullOrEmpty()]
        [string]$SiteServer,

        [Parameter(Mandatory = $true)]
        [string]
        $SiteCode
    )
    begin {
        try {
            Add-Type -Path (Join-Path -Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName -ChildPath "Microsoft.ConfigurationManagement.ApplicationManagement.dll") -ErrorAction Stop
            Add-Type -Path (Join-Path -Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName -ChildPath "Microsoft.ConfigurationManagement.ApplicationManagement.Extender.dll") -ErrorAction Stop
            Add-Type -Path (Join-Path -Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName -ChildPath "Microsoft.ConfigurationManagement.ApplicationManagement.MsiInstaller.dll") -ErrorAction Stop
        }
        catch [System.UnauthorizedAccessException] {
            Write-OutputBox -OutputBoxMessage "Access denied when attempting to load ApplicationManagement dll's" -Type ERROR ; break
        }
        catch [System.Exception] {
            Write-OutputBox -OutputBoxMessage "Unable to load required ApplicationManagement dll's. Make sure that you're running this tool on system where the ConfigMgr console is installed and that you're running the tool elevated" -Type ERROR ; break
        }
    }
    process {
        $counter = 0
        $PkgList = @()
        $Packages = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class "SMS_Package" -ComputerName $SiteServer
        $PackagesCount = $Packages.Count
        foreach ($Package in $Packages) {
            Write-Progress -Activity "Getting Package Info" -Status "$($Package.Name)" -PercentComplete ((++$counter / $PackagesCount) * 100)
            $PkgInfo = New-Object -TypeName PSObject
            $PkgInfo | Add-Member -MemberType NoteProperty -Name "Name" -Value $Package.Name
            $PkgInfo | Add-Member -MemberType NoteProperty -Name "Id" -Value $Package.PackageID
            if ($Package.PkgSourcePath) {
                $PkgInfo | Add-Member -MemberType NoteProperty -Name "ContentPath" -Value $Package.PkgSourcePath
            }
            else {
                continue
            }
            $PkgList += $PkgInfo
        }
        Write-Progress -Activity "Done" -Completed
        return $PkgList
    }
}

Export-ModuleMember -Function Get-CMApplicationContentPaths
Export-ModuleMember -Function Get-CMPackageContentPaths
