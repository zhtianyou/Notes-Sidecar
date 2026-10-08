#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
derived_data="${1:-${project_root}/.build/app-store-sandbox}"
app_path="${derived_data}/Build/Products/Release/NotesSidecar.app"
extension_path="${app_path}/Contents/PlugIns/NotesSidecarShare.appex"
entitlements_path="$(mktemp -t notes-sidecar-entitlements).plist"
extension_entitlements_path="$(mktemp -t notes-sidecar-share-entitlements).plist"
trap 'rm -f "${entitlements_path}" "${extension_entitlements_path}"' EXIT

xcodebuild \
  -project "${project_root}/NotesSidecar.xcodeproj" \
  -scheme NotesSidecar \
  -configuration Release \
  -derivedDataPath "${derived_data}" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null

# App Groups normally require a paid Team provisioning profile. For the free,
# pre-enrollment verification path, sign the already-built nested extension and
# containing app ad hoc so their final entitlement structure can still be
# inspected. This does not claim that the shared container is provisioned.
codesign --force --sign - --timestamp=none \
  --entitlements "${project_root}/App/ShareExtension/NotesSidecarShare.entitlements" \
  "${extension_path}"
codesign --force --sign - --timestamp=none --options runtime \
  --entitlements "${project_root}/App/Resources/NotesSidecar.Release.entitlements" \
  "${app_path}"

codesign -d --entitlements :- "${app_path}" 2>&1 | sed -n '/<?xml/,$p' > "${entitlements_path}"
codesign -d --entitlements :- "${extension_path}" 2>&1 | sed -n '/<?xml/,$p' > "${extension_entitlements_path}"

assert_plist_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${plist}")"
  if [[ "${actual}" != "${expected}" ]]; then
    print -u2 -- "FAIL: ${key} expected '${expected}', got '${actual}'"
    exit 1
  fi
}

assert_plist_value "${entitlements_path}" "com.apple.security.app-sandbox" "true"
assert_plist_value "${entitlements_path}" "com.apple.security.network.client" "true"
assert_plist_value "${entitlements_path}" "com.apple.security.automation.apple-events" "true"
assert_plist_value "${entitlements_path}" "com.apple.security.temporary-exception.apple-events:0" "com.apple.Notes"
assert_plist_value "${entitlements_path}" "com.apple.security.application-groups:0" "group.com.youwin.NotesSidecar"
assert_plist_value "${extension_entitlements_path}" "com.apple.security.app-sandbox" "true"
assert_plist_value "${extension_entitlements_path}" "com.apple.security.application-groups:0" "group.com.youwin.NotesSidecar"

assert_plist_value "${extension_path}/Contents/Info.plist" "NSExtension:NSExtensionPointIdentifier" "com.apple.share-services"
assert_plist_value "${extension_path}/Contents/Info.plist" "NSExtension:NSExtensionAttributes:NSExtensionActivationRule:NSExtensionActivationSupportsText" "true"

usage_description="$(/usr/libexec/PlistBuddy -c 'Print :NSAppleEventsUsageDescription' "${app_path}/Contents/Info.plist")"
if [[ -z "${usage_description}" ]]; then
  print -u2 -- "FAIL: NSAppleEventsUsageDescription is empty"
  exit 1
fi

print -- "PASS: Release build is sandboxed, declares Notes Apple Events access, and embeds a sandboxed Share Extension with the shared App Group."
print -- "APP_PATH=${app_path}"
