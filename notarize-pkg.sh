#!/bin/sh
# Notarize a signed installer package with the Apple developer account that is
# signed into Xcode (Settings > Accounts); no notarytool profile is needed.
#
# Xcode only uploads archives, so the package travels inside a disposable app
# archive. Apple's notary service scans nested containers, so the ticket also
# covers the package, which is then stapled and assessed. The wrapper app is
# never distributed.
#
# Usage: notarize-pkg.sh PACKAGE "Developer ID Application: Name (TEAMID)" EXECUTABLE
#   EXECUTABLE: any Mach-O tool, used as the wrapper app's main executable.
set -e
package="$1"
identity="$2"
executable="$3"
timeout="${NOTARIZE_TIMEOUT:-3600}"
if [ ! -f "$package" ] || [ -z "$identity" ] || [ ! -f "$executable" ]; then
    echo "Usage: $0 PACKAGE APPLICATION-IDENTITY EXECUTABLE" >&2
    exit 64
fi
team=$(printf '%s\n' "$identity" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')
if [ -z "$team" ]; then
    echo "Cannot read the team ID from \"$identity\"" >&2
    exit 64
fi

stage=$(mktemp -d "${TMPDIR:-/tmp}/satsmart-notary.XXXXXX")
archive="$stage/NotarizationWrapper.xcarchive"
app="$archive/Products/Applications/NotarizationWrapper.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$executable" "$app/Contents/MacOS/NotarizationWrapper"
cp "$package" "$app/Contents/Resources/"

plist() { /usr/libexec/PlistBuddy -c "$2" "$1" >/dev/null; }
info="$app/Contents/Info.plist"
plist "$info" "Add :CFBundleExecutable string NotarizationWrapper"
plist "$info" "Add :CFBundleIdentifier string fi.dungeon.SATSMARTDriver.notarization-wrapper"
plist "$info" "Add :CFBundleName string NotarizationWrapper"
plist "$info" "Add :CFBundlePackageType string APPL"
plist "$info" "Add :CFBundleShortVersionString string 1.0"
plist "$info" "Add :CFBundleVersion string 1"
codesign --force --sign "$identity" --options runtime --timestamp "$app"

meta="$archive/Info.plist"
plist "$meta" "Add :ArchiveVersion integer 2"
plist "$meta" "Add :Name string NotarizationWrapper"
plist "$meta" "Add :SchemeName string NotarizationWrapper"
plist "$meta" "Add :CreationDate date $(date -u '+%a %b %d %H:%M:%S UTC %Y')"
plist "$meta" "Add :ApplicationProperties:ApplicationPath string Applications/NotarizationWrapper.app"
plist "$meta" "Add :ApplicationProperties:CFBundleIdentifier string fi.dungeon.SATSMARTDriver.notarization-wrapper"
plist "$meta" "Add :ApplicationProperties:CFBundleShortVersionString string 1.0"
plist "$meta" "Add :ApplicationProperties:CFBundleVersion string 1"
plist "$meta" "Add :ApplicationProperties:SigningIdentity string $identity"
plist "$meta" "Add :ApplicationProperties:Team string $team"

options="$stage/ExportOptions.plist"
plist "$options" "Add :method string developer-id"
plist "$options" "Add :destination string upload"
plist "$options" "Add :signingStyle string automatic"
plist "$options" "Add :teamID string $team"
plist "$options" "Add :manageAppVersionAndBuildNumber bool false"

echo "Uploading $package for notarization (team $team)"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" \
    -exportPath "$stage/upload" -allowProvisioningUpdates

# exportNotarizedApp fails until Apple has decided. A rejection leaves the
# notary log in the archive; anything else means "still processing".
waited=0
until xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$stage/notarized" \
        >"$stage/export.log" 2>&1; do
    log=$(find "$archive/Submissions" -name notarization-log.json 2>/dev/null | head -1)
    if [ -n "$log" ]; then
        echo "Notarization rejected; log: $log" >&2
        /usr/bin/python3 -c 'import json,sys
for i in json.load(open(sys.argv[1])).get("issues") or []:
    print("  %s: %s (%s)" % (i.get("path","").split(".app/")[-1], i.get("message"), i.get("architecture")))' "$log" >&2
        exit 1
    fi
    if [ "$waited" -ge "$timeout" ]; then
        echo "No notarization result after ${timeout}s; see $stage/export.log" >&2
        exit 1
    fi
    sleep 30
    waited=$((waited + 30))
    rm -rf "$stage/notarized"
done

xcrun stapler staple "$package"
xcrun stapler validate "$package"
spctl --assess --type install -vv "$package"
rm -rf "$stage"
