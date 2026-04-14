# App Store Connect Workflow

How to archive, upload, and manage Jataayu builds on App Store
Connect. Covers one-time setup and the ongoing release-to-TestFlight
flow.

---

## Prerequisites (one-time)

### CLI tools

| Tool | Install | Purpose |
|------|---------|---------|
| `asc` | `brew install tddworks/tap/asc-cli` | App Store Connect CLI — builds, TestFlight, versions |
| `xcodebuild` | Ships with Xcode | Archive + export + upload |

### App Store Connect API key

The `asc` CLI authenticates via an API key (.p8), not your Apple ID.

1. Go to [App Store Connect → Integrations → API](https://appstoreconnect.apple.com/access/integrations/api)
2. Click **Generate API Key** (or "Request Access" if first time)
3. Name: `Jataayu CLI`, Role: **Admin**
4. Download the `.p8` file (available once only)
5. Store it securely:
   ```bash
   mkdir -p ~/.appstoreconnect/private_keys
   mv ~/Downloads/AuthKey_<KEY_ID>.p8 ~/.appstoreconnect/private_keys/
   chmod 600 ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
   ```
6. Authenticate:
   ```bash
   asc auth login \
     --key-id <KEY_ID> \
     --issuer-id <ISSUER_ID> \
     --private-key-path ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 \
     --name jataayu
   ```
7. Verify: `asc auth check`

### Signing identity

The archive build requires an Apple Distribution certificate.
Verify it exists:

```bash
security find-identity -v -p codesigning | grep "Apple Distribution"
```

Should show your `Apple Distribution: <TEAM_NAME> (<TEAM_ID>)` identity.

---

## Uploading a build to TestFlight

After tagging a release (`make release VERSION=X.Y.Z` + commit +
tag + push), upload to TestFlight:

### 1. Archive

```bash
xcodebuild archive \
  -project Jataayu.xcodeproj \
  -scheme Jools \
  -configuration Release \
  -archivePath /tmp/Jataayu.xcarchive \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=<TEAM_ID>
```

### 2. Export + upload

Create `/tmp/ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string><!-- your TEAM_ID --></string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

Then export and upload in one step:

```bash
xcodebuild -exportArchive \
  -archivePath /tmp/Jataayu.xcarchive \
  -exportOptionsPlist /tmp/ExportOptions.plist \
  -exportPath /tmp/JataayuExport \
  -allowProvisioningUpdates
```

Wait for "Upload succeeded" + "Uploaded package is processing."

### 3. Handle encryption compliance

After processing completes (~2-5 min), App Store Connect may
prompt for export compliance (encryption). Answer via the web UI
or `asc` CLI. Jataayu uses HTTPS only (no custom encryption), so
the answer is typically "No" for proprietary encryption.

### 4. Verify

```bash
asc builds list --output table
```

The build auto-distributes to the "Dev Team" internal TestFlight
group.

---

## Common `asc` commands

```bash
# Auth
asc auth check                       # verify credentials
asc auth list                        # list saved accounts

# Apps
asc apps list --output table         # list apps

# Builds
asc builds list --output table       # list all builds
asc testflight groups list           # list TestFlight groups

# Interactive
asc tui                              # terminal UI for browsing
```

---

## App details

| Field | Where to find |
|-------|---------------|
| App ID | `asc apps list` |
| Bundle ID | `project.yml` → `PRODUCT_BUNDLE_IDENTIFIER` |
| Team ID | `project.yml` → `DEVELOPMENT_TEAM` or Keychain → signing certificate |
| TestFlight group | `asc testflight groups list` |
