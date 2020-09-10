# Update-CMScriptContent

Finds and replaces the content in text-based files and redistributes any referencing Configuration Manager Applications and Packages. 

## Usage

Search Only
```powershell
.\Update-CMScriptContent.ps1 `
  -SearchBase "\\myfileserver.example.com\files\" `
  -SearchStrings "\\myoldfileserver\","\\myoldfileserver.example.com\"
```

Search and Replace
```powershell
.\Update-CMScriptContent.ps1 `
  -SearchBase "\\myfileserver.example.com\files\" `
  -SearchStrings "\\myoldfileserver\", "\\myoldfileserver.example.com\" `
  -ReplaceString "\\myfileserver.domain.com\" `
  -SiteServer "mecmsiteserver.example.com" `
  -SiteCode "S01"
```

## Features

* Recursively finds files with search strings
* Can be run in search only mode
* Can incorporate multiple search strings
* Reports errors and successes in colored output
* Creates backups of files before making changes
* Updates distribution points for applications and packages as files are changed
* Creates transcript of all actions

## Requirements
* Powershell 5.1
* Configuration Manager installed on the local machine
* Access rights to read and distribute applications and packages on Configuration Manager site
* Read/Write access rights to the file share with files to be updated
