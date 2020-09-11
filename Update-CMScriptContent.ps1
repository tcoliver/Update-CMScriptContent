[CmdletBinding(DefaultParameterSetName = "SearchOnly")]
param (
    # UNC root for search
    [Parameter(Mandatory = $true)]
    [string]
    $SearchBase,

    # String to find in FileTypes
    [Parameter(Mandatory = $true)]
    [string[]]
    $SearchStrings,

    # String to replace found strings
    [Parameter(Mandatory = $false, ParameterSetName = "Replace")]
    [string]
    $ReplaceString,

    # File extensions to include in search
    [Parameter()]
    [string[]]
    $Include = @("bat", "ps1", "sh", "cmd", "txt"),

    # Do not confirm replace
    [Parameter(ParameterSetName = "Replace")]
    [switch]
    $Force,

    # SiteServer to get Applications
    [Parameter(Mandatory = $false, ParameterSetName = "SearchOnly")]
    [Parameter(Mandatory = $true, ParameterSetName = "Replace")]
    [string]
    $SiteServer,

    # SiteCode to get Applications
    [Parameter(Mandatory = $false, ParameterSetName = "SearchOnly")]
    [Parameter(Mandatory = $true, ParameterSetName = "Replace")]
    [string]
    $SiteCode,

    # Path to save transcript
    [Parameter()]
    [string]
    $TranscriptPath = "./UpdateCMScriptContent.log",

    # Extension for the backup files
    [Parameter(ParameterSetName = "Replace")]
    [string]
    $BackupExtension = "sr_bkp"
)

BEGIN {
    ############################### Setup Search ###############################
    $BackupExtension = $BackupExtension -replace "^\.?", "."
    $Include = $Include | ForEach-Object { $_ -replace "^\.?", "." }
    $SearchExp = "(" + (($SearchStrings | ForEach-Object { [regex]::Escape($_) }) -join "|") + ")"

    function Get-IsPathPart {
        param (
            [Parameter(Position=0)]
            [string]$FilePath, 
            
            [Parameter(Position=1)]
            [string]$PathPart
        )
        $FilePathDomain = $FilePath | Select-String -Pattern "(?<=\\\\.*?)\..*?(?=\\.*)" | 
            Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value
        $PathPartDomain = $PathPart | Select-String -Pattern "(?<=\\\\.*?)\..*?(?=\\.*)" | 
            Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value
        if ($FilePathDomain -and $PathPartDomain -and ($FilePathDomain -ne $PathPartDomain) ) {
            return $false
        }
        $FilePath = $FilePath -isplit "(?<=\\\\.*?)\..*?(?=\\.*)" -join ""
        $PathPart = $PathPart -isplit "(?<=\\\\.*?)\..*?(?=\\.*)" -join ""
        return $FilePath -imatch [regex]::Escape($PathPart)
    }

    function Update-FileContent {
        param (
            [Parameter(Mandatory)]
            [System.IO.FileInfo]
            $File,

            [Parameter(Mandatory)]
            [string]
            $SearchExp,

            [Parameter(Mandatory)]
            [string]
            $ReplaceString
        )
        try {
            Copy-Item -Path $File.PSPath -Destination "$($FILE.PSPath)$BackupExtension" -ErrorAction "Stop" | Out-Null
        } catch {
            Write-Host "ERROR: Failed to backup '$($File.FullName)'. Skipping." -ForegroundColor "Red"
            return $false
        }
        
        try {
            (Get-Content -Path $File.PSPath -Raw -ErrorAction "Stop") -ireplace "$SearchExp", "$ReplaceString" | 
                Set-Content -Path $File.PSPath -ErrorAction "Stop"
            Write-Host "INFO:  Successfuly updated '$($File.FullName)'" -ForegroundColor "Green"
        }
        catch {
            Write-Host "ERROR: Failed to write content for '$($File.FullName)'. Skipping." -ForegroundColor "Red"
            return $false
        }
        return $true
    }

    Start-Transcript -Path $TranscriptPath

    ########################### Import dependancies ############################

    try {
        Import-Module "$PSScriptRoot\Get-CMContentPaths\Get-CMContentPaths.psm1" -ErrorAction Stop
    } catch {
        Write-Host "ERROR: Failed to import dependancies. Exiting." -ForegroundColor "Red"
        Stop-Transcript
        exit 1
    }

    ############################## Verify Replace ##############################
    if (-Not $Force -And $ReplaceString) {
        Write-Host @"
You have included a `$ReplaceString. This will replace all instances of the search strings with the replace string.
Search String(s): '$($SearchStrings -join "' and '")' 
Replace String:   '$ReplaceString'. 
"@ -ForegroundColor "Yellow"
        $response = Read-Host -Prompt "Are you sure you would like to continue (yes/no)?"
        if ($response.ToLower() -ne "yes") {
            Write-Host "INFO:  Stopping"
            Stop-Transcript
            exit 0
        }
    }

    ####################### Mount Endpoint Manager site ########################
    if ($ReplaceString) {
        Write-Host "INFO:  Mounting Endpoint Manager site"
        $OriginalLocation = Get-Location 
        if($null -eq (Get-Module ConfigurationManager)) {
            try {
                Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" -Global
            } catch {
                Write-Host "ERROR: Unable to import the ConfigurationManager.psd1 Cmdlets. Exiting." -ForegroundColor "Red"
                exit 1
            }
        }
        if($null -eq (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
            try {
                New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer -ErrorAction "Stop" | Out-Null
            } catch {
                Write-Host "ERROR: Unable to mount the Endpoint Manager site. Exiting." -ForegroundColor "Red"
                exit 1
            }
        }
    }
}

PROCESS {
    ################## Get files with extentions in $Include ##################
    $Activity = "Searching for included file types at '$SearchBase'"
    Write-Progress -Activity $Activity -Status "This may take a while..."
    Write-Host "INFO:  Starting search for files."

    $FilesToScan = Get-ChildItem -File -Recurse -Path $SearchBase -ErrorAction SilentlyContinue | 
        Where-Object { $_.Extension -in $Include } | Sort-Object -Property "FullName"
    $FilesToScanCount = $FilesToScan.Count

    Write-Host "INFO:  Got $FilesToScanCount files from '$SearchBase'"
    if (-Not $FilesToScan) {
        Write-Host "WARN:  No files were found with included extentions. Exiting." -ForegroundColor "Yellow"
        Stop-Transcript
        exit 0
    }

    ################### Search each file for search strings ###################
    Write-Host "INFO:  Starting file scan for '$($SearchStrings -join "' and '")'"
    $Activity = "Scanning $FilesToScanCount files for '$($SearchStrings -join "' and '")'"
    $Count = 0
    $FilesWithString = New-Object -TypeName System.Collections.ArrayList

    foreach ($File in $FilesToScan) {
        Write-Progress -Activity $Activity -CurrentOperation "$($File.FullName)" -PercentComplete ((++$Count / $FilesToScanCount) * 100)
        try {
            if ((Get-Content -Path $File.PSPath -Raw -ErrorAction Stop) -imatch "$SearchExp") {
                $FilesWithString.Add($File) | Out-Null
                Write-Host "INFO:  Found '$($File.FullName)'" -ForegroundColor "Green"
            }
        }
        catch {
            Write-Host "WARN: Unable to read content of '$($File.FullName)'. Skipping." -ForegroundColor "Yellow"
        }
    }
    $FilesWithStringCount = $FilesWithString.Count

    Write-Host "INFO:  Found '$($SearchStrings -join "' or '")' in $FilesWithStringCount files"
    if (-Not $FilesWithStringCount) {
        Write-Host "INFO:  No files were found content that includes the search strings. Exiting"
        Stop-Transcript
        exit 0
    }
    
    ########### Replace search string in content with replace string ###########
    if ($ReplaceString) {
        $Activity = "Writing changes to files"
        $Status = "'$($SearchStrings -join "' and '")' -> '$ReplaceString'"
        $Count = 0
        $FilesWithStringReplaced = New-Object -TypeName System.Collections.ArrayList
        
        try {
            Write-Host "INFO:  Getting application with content from Endpoint Manager"
            $CMAppList = Get-CMApplicationContentPaths -SiteServer $SiteServer -SiteCode $SiteCode
            Write-Host "INFO:  Got $($CMAppList.Count) applications with content"
        } catch {
            Write-Host "WARN:  $($CMAppList.Count) applications with content" -ForegroundColor "Yellow"
        }

        try {
            Write-Host "INFO:  Getting packages with content from Endpoint Manager"
            $CMPkgList = Get-CMPackageContentPaths -SiteServer $SiteServer -SiteCode $SiteCode
            Write-Host "INFO:  Got $($CMPkgList.Count) packages with content"
        } catch {
            Write-Host "WARN:  $($CMPkgList.Count) packages with content" -ForegroundColor "Yellow"
        }
        
        Write-Host "INFO:  Starting string replacement with '$ReplaceString'"

        ######## Match found files with MECM application content paths ########
        Write-Host "INFO:  Starting replacement for application affiliated files"
        $ErrorCount = 0 
        foreach ($App in $CMAppList) {
            foreach ($DepType in $App.DeploymentTypes){
                $MatchedFiles = @()
                $NeedsRedist = $false
                foreach ($ContentPath in $DepType.ContentPaths) {
                    $MatchedFiles += $FilesWithString | Where-Object { Get-IsPathPart -FilePath $_.FullName -PathPart $ContentPath }
                }
                if ($MatchedFiles) {
                    $NeedsRedist = $true
                    foreach ($File in $MatchedFiles) {
                        Write-Progress -Activity $Activity -Status $Status -CurrentOperation "$($App.Name)" -PercentComplete ((++$Count / $FilesWithStringCount) * 100)
                        $Success = Update-FileContent -File $File -SearchExp $SearchExp -ReplaceString $ReplaceString
                        if ($Success) { 
                            $FilesWithString.Remove($File) | Out-Null
                            $FilesWithStringReplaced.Add($File) | Out-Null 
                        } else { 
                            $ErrorCount++ 
                        }
                    }
                } else {
                    foreach ($ContentPath in $DepType.ContentPaths) {
                        if ($FilesWithStringReplaced | Where-Object { Get-IsPathPart -FilePath $_.FullName -PathPart $ContentPath }) {
                            $NeedsRedist = $true
                        }
                    }
                }
                if ($NeedsRedist) {
                    Write-Host "INFO:  '$($App.Name):$($DepType.Name)' needs distribution point update"
                    try {
                        Set-Location "$($SiteCode):\"
                        Update-CMDistributionPoint -ApplicationName "$($App.Name)" -DeploymentTypeName "$($DepType.Name)" -ErrorAction "Stop"
                        Write-Host "INFO:  Successfully started distribution point update for '$($App.Name):$($DepType.Name)'"
                    } catch {
                        $ErrorCount++
                        Write-Host "ERROR: Failed to start distribution point update for '$($App.Name):$($DepType.Name)'" -ForegroundColor "Red"
                    } finally {
                        Set-Location $OriginalLocation.Path

                    }
                }
            }
            
            
        }
        if ($ErrorCount) {
            Write-Host "WARN:  Application affiliated file updates completed with $ErrorCount errors." -ForegroundColor "Yellow"
        }

        ########## Match found files with MECM package content paths ##########
        Write-Host "INFO:  Starting replacement for package affiliated files"
        $ErrorCount = 0 
        foreach ($Pkg in $CMPkgList) {
            $NeedsRedist = $false
            $MatchedFiles = $FilesWithString | Where-Object { Get-IsPathPart -FilePath $_.FullName -PathPart $Pkg.ContentPath }
            if ($MatchedFiles) {
                $NeedsRedist = $true
                foreach ($File in $MatchedFiles) {
                    Write-Progress -Activity $Activity -Status $Status -CurrentOperation "$($Pkg.Name)" -PercentComplete ((++$Count / $FilesWithStringCount) * 100)
                    $Success = Update-FileContent -File $File -SearchExp $SearchExp -ReplaceString $ReplaceString
                    if ($Success) { 
                        $FilesWithString.Remove($File) | Out-Null
                        $FilesWithStringReplaced.Add($File) | Out-Null 
                    } else { 
                        $ErrorCount++ 
                    }
                }
            } else {
                if ($FilesWithStringReplaced | Where-Object { Get-IsPathPart -FilePath $_.FullName -PathPart $Pkg.ContentPath }) {
                    $NeedsRedist = $true
                }
            }
            if ($NeedsRedist) {
                Write-Host "INFO:  '$($Pkg.Name)' needs distribution point update"
                try{
                    Set-Location "$($SiteCode):\"
                    Update-CMDistributionPoint -PackageName "$($Pkg.Name)" -ErrorAction "Stop"
                    Write-Host "INFO:  Successfully started distribution point update for '$($Pkg.Name)'" -ForegroundColor Green
                } catch {
                    $ErrorCount++
                    Write-Host "ERROR: Failed to start distribution point update for $($Pkg.Name)" -ForegroundColor "Red"
                } finally {
                    Set-Location $OriginalLocation.Path
                }
            }
        }
        if ($ErrorCount) {
            Write-Host "WARN:  Package affiliated file updates completed with $ErrorCount errors." -ForegroundColor "Yellow"
        }

        ################### Replace remaining files content ###################
        Write-Host "INFO:  Starting replacement for non-affiliated files"
        $ErrorCount = 0 
        foreach ($File in $FilesWithString) {
            Write-Progress -Activity $Activity -Status $Status -CurrentOperation "$($File.FullName)" -PercentComplete ((++$Count / $FilesWithStringCount) * 100)
            $Success = Update-FileContent -File $File -SearchExp $SearchExp -ReplaceString $ReplaceString
            if (-Not $Success) { $ErrorCount++ }
        }
        if ($ErrorCount) {
            Write-Host "WARN:  Non-affiated file updates completed with $ErrorCount errors." -ForegroundColor "Yellow"
        }
    }
}

END {
    Write-Host "INFO:  Operation Complete"
    Write-Progress -Activity "Operation Complete" -Completed
    Stop-Transcript
}