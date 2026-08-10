<#
  ManifestVersion.psm1

  IIS PIVOT -- Manifest version/compatibility check.

  WHY THIS EXISTS:
  Every manifest this tool produces (site export JSON, from scripts
  like 01-Inspect-IIS.ps1) carries a schemaVersion field. Up to now,
  nothing ever actually reads that field before a restore -- if the
  manifest format changes in the future, an old manifest could
  silently be fed into a restore operation with no warning, and
  produce wrong/partial results.

  This module fixes that: before any future restore operation runs,
  it should call Assert-ManifestCompatible on the loaded manifest
  first. If the manifest's schemaVersion isn't one this version of
  the tool understands, it throws immediately -- before anything on
  the target server is touched.

  A NOTE ON EXISTING MANIFESTS:
  Scripts already proven working (01-Inspect-IIS.ps1 and others) used
  ad-hoc version strings like "0.1-combined-inspection" before this
  module existed. Those scripts are NOT being changed by this module
  (a deliberate decision -- see project chat history). This means
  manifests produced by those scripts will correctly show up as
  "unknown schema version" when checked here. That is the expected,
  correct behavior, not a bug: those files predate any real
  versioning scheme, so the tool genuinely cannot promise it
  understands their format.

  GOING FORWARD:
  New manifest-producing scripts (or updated versions of existing
  ones, as a deliberate separate step) should stamp
  schemaVersion = $CurrentManifestSchemaVersion (below) rather than
  inventing a new ad-hoc string.

  RUN THIS ON: your laptop (this is a module, imported by other
  scripts -- it does nothing on its own).
#>

$ErrorActionPreference = 'Stop'

# The version new manifests should be stamped with going forward.
$Script:CurrentManifestSchemaVersion = '1.0'

# Every version this build of the tool is able to safely read/restore.
# Add to this list (rather than replacing it) when a new manifest
# version is introduced but old ones should still be restorable.
$Script:SupportedManifestSchemaVersions = @('1.0')

function Get-ManifestSchemaInfo {
    <#
      Returns the current/supported version info this module knows
      about, mainly for scripts that want to print it or stamp new
      manifests with the current version.
    #>
    return [ordered]@{
        currentVersion    = $Script:CurrentManifestSchemaVersion
        supportedVersions = $Script:SupportedManifestSchemaVersions
    }
}

function Test-ManifestCompatibility {
    <#
      Checks a loaded manifest object (already parsed from JSON, e.g.
      via ConvertFrom-Json) against the list of supported schema
      versions. Returns an [ordered] result object rather than
      throwing, so callers that just want to report status (not abort)
      can do so.
    #>
    param(
        [Parameter(Mandatory)]
        $Manifest
    )

    $version = $Manifest.schemaVersion

    if ([string]::IsNullOrWhiteSpace($version)) {
        return [ordered]@{
            isCompatible   = $false
            manifestVersion = $null
            reason         = "Manifest has no schemaVersion field at all -- cannot determine its format. Refusing to treat it as safe to restore."
        }
    }

    if ($Script:SupportedManifestSchemaVersions -contains $version) {
        return [ordered]@{
            isCompatible   = $true
            manifestVersion = $version
            reason         = "schemaVersion '$version' is in the supported list."
        }
    }

    return [ordered]@{
        isCompatible   = $false
        manifestVersion = $version
        reason         = "schemaVersion '$version' is not in the supported list ($($Script:SupportedManifestSchemaVersions -join ', ')). This may be a manifest from before the versioning scheme existed, or from a newer/incompatible tool version."
    }
}

function Assert-ManifestCompatible {
    <#
      Same check as Test-ManifestCompatibility, but throws on
      incompatibility instead of returning a result -- intended for
      use as a hard gate at the start of a real restore operation,
      where "continue anyway" should never be the silent default.
    #>
    param(
        [Parameter(Mandatory)]
        $Manifest
    )

    $result = Test-ManifestCompatibility -Manifest $Manifest
    if (-not $result.isCompatible) {
        throw "Assert-ManifestCompatible: $($result.reason)"
    }
    return $result
}

Export-ModuleMember -Function Get-ManifestSchemaInfo, Test-ManifestCompatibility, Assert-ManifestCompatible
