function GetUninstallPath() {
  param(
    [Parameter(Mandatory = $true)]
    [string]$product
  )
  $regUninstallDir = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\'
  $regUninstallDirWow64 = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\'

  $uninstallPaths = $(Get-ChildItem $regUninstallDir).Name

  if (Test-Path $regUninstallDirWow64) {
    $uninstallPaths += $(Get-ChildItem $regUninstallDirWow64).Name
  }

  $uninstallPath = $uninstallPaths -match "$product [\d\.]+ \([^\s]+ [a-zA-Z\-]+\)" | Select-Object -First 1
  return $uninstallPath
}

function GetLocale {
  param(
    [Parameter(Mandatory = $true)]
    [string]$localeFile,
    [Parameter(Mandatory = $true)]
    [string]$product
  )
  #$availableLocales = Get-WebContent $localeUrl 2>$null
  $availableLocales = Get-Content $localeFile | ForEach-Object { $_ -split '\|' | Select-Object -First 1 } | Select-Object -Unique
  Write-Debug "$($availableLocales.Count) locales are stored.`n$availableLocales"

  $PackageParameters = Get-PackageParameters

  if ($PackageParameters['l']) {
    $localeFromPackageParameters = $PackageParameters['l']
    Write-Verbose "User chooses '$localeFromPackageParameters' as a locale..."
    $localeFromPackageParametersTwoLetter = $localeFromPackageParameters -split '\-' | Select-Object -First 1
    Write-Verbose "With fallback to '$localeFromPackageParametersTwoLetter' as locale..."
  }

  $uninstallPath = GetUninstallPath -product $product

  $alreadyInstalledLocale = $uninstallPath -replace '.+\s([a-zA-Z\-]+)\)', '$1'
  Write-Verbose "Installed locale is: '$alreadyInstalledLocale'..."

  $systemLocalizeAndCountry = (Get-UICulture).Name
  $systemLocaleTwoLetter = (Get-UICulture).TwoLetterISOLanguageName

  $fallbackLocale = 'en-US'
  if ([string]::IsNullOrEmpty($localeFromPackageParameters) -or [string]::IsNullOrEmpty($localeFromPackageParametersTwoLetter)) {
    Write-Verbose "System locale is: '$systemLocalizeAndCountry'..."
    $urlParts = @( 'htt', 'mozilla' )
    $Response = Invoke-WebRequest "$($urlParts[0])ps://www.$($urlParts[1]).org/" -UseBasicParsing -Headers @{'Accept-Language' = $systemLocalizeAndCountry } -MaximumRedirection 0 -ErrorAction Ignore
    $fallbackLocale = $Response.Headers.Location.Trim('/')
    Write-Verbose "Fallback locale is: '$fallbackLocale'..."
  }
  else {
    Write-Verbose 'Locale was passed as a package parameter. Will not query external website.'
  }

  $locales = $localeFromPackageParameters, $localeFromPackageParametersTwoLetter, `
    $alreadyInstalledLocale, $systemLocalizeAndCountry, $systemLocaleTwoLetter, `
    $fallbackLocale

  foreach ($locale in $locales) {
    Write-Debug "Testing locale $locale of whether we have the information or not"
    $localeMatch = $availableLocales | Where-Object { $_ -eq $locale } | Select-Object -First 1
    if ($localeMatch -and $locale -ne $null) {
      Write-Host "Using locale '$locale'..."
      break
    }
  }

  return $locale
}

function AlreadyInstalled() {
  param(
    [Parameter(Mandatory = $true)]
    [string]$product,
    [Parameter(Mandatory = $true)]
    [string]$version
  )
  $uninstallEntry = $(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$product $version*"
  )
  $uninstallEntryWow64 = $(
    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$product $version*"
  )

  if ((Test-Path $uninstallEntry) -or (Test-Path $uninstallEntryWow64)) {
    return $true
  }

  return $false
}

function Get-32bitOnlyInstalled() {
  param(
    [Parameter(Mandatory = $true)]
    [string]$product
  )
  $systemIs64bit = Get-OSArchitectureWidth 64

  if (-Not $systemIs64bit) {
    return $false
  }

  $registryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )

  $installedVersions = Get-ChildItem $registryPaths | Where-Object { $_.Name -match "$product [\d\.]+ \(x(64|86)" }

  if (
    $installedVersions -match 'x86' `
      -and $installedVersions -notmatch 'x64' `
      -and $systemIs64bit
  ) {
    return $true
  }
}

function GetChecksums() {
  param(
    [Parameter(Mandatory = $true)]
    [string]$language,
    [Parameter(Mandatory = $true)]
    $checksumFile
  )
  Write-Debug "Loading checksums from: $checksumFile"
  $checksumContent = Get-Content $checksumFile
  $checksum32 = ($checksumContent -match "$language\|32") -split '\|' | Select-Object -Last 1
  $checksum64 = ($checksumContent -match "$language\|64") -split '\|' | Select-Object -Last 1

  return @{
    'Win32' = $checksum32
    'Win64' = $checksum64
  }
}
