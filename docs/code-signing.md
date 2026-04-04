# SLATE Code Signing Guide

## Overview

This document explains how to set up and maintain code signing for the SLATE desktop application. Proper code signing ensures:

- User trust (verified developer identity)
- macOS Gatekeeper compatibility
- Automatic updates functionality
- Distribution outside App Store

## Prerequisites

### Apple Developer Account

1. **Enroll in Apple Developer Program**
   - Visit [developer.apple.com](https://developer.apple.com)
   - Choose "Organization" type (required for distribution)
   - Annual fee: $99/year

2. **Generate Certificates**
   ```bash
   # Generate Certificate Signing Request (CSR)
   openssl req -new -newkey rsa:2048 -nodes -keyout private.key -out certificate.csr
   ```

3. **Download Required Certificates**
   - Development: "Apple Development"
   - Distribution: "Developer ID Application"
   - Xcode will automatically manage these if signed in

### Team ID and Bundle Identifier

- **Team ID**: Found in Apple Developer portal (10-character string)
- **Bundle ID**: `com.mountaintoppictures.slate`
- **App Store Connect**: Not required for direct distribution

## Setup Instructions

### 1. Xcode Configuration

Open `apps/desktop/SLATE.xcodeproj` and configure:

1. **Project Settings**
   - Select SLATE project
   - Signing & Capabilities tab
   - Team: Select your developer account
   - Bundle Identifier: `com.mountaintoppictures.slate`

2. **Code Signing Identity**
   - Debug: Apple Development
   - Release: Developer ID Application

3. **Entitlements**
   - Create `SLATE.entitlements` file
   - Add required entitlements (see below)

### 2. Entitlements File

Create `apps/desktop/SLATE.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Network access -->
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    
    <!-- File system access -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
    <key>com.apple.security.files.pictures.read-write</key>
    <true/>
    <key>com.apple.security.files.movies.read-write</key>
    <true/>
    
    <!-- Hardware access -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.device.camera</key>
    <true/>
    
    <!-- App Sandbox -->
    <key>com.apple.security.app-sandbox</key>
    <true/>
    
    <!-- XPC Services -->
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.mountaintoppictures.slate</string>
    </array>
</dict>
</plist>
```

### 3. Provisioning Profiles

1. **Development Profile**
   - Automatically created by Xcode
   - Includes development certificates
   - Valid for 1 year

2. **Distribution Profile**
   - Create in Apple Developer portal
   - Select "Mac App Store" > "Developer ID"
   - Download and install in Xcode

## Build Process

### Local Builds

```bash
# Debug build (development certificate)
xcodebuild -project SLATE.xcodeproj \
           -scheme SLATE \
           -configuration Debug \
           clean build

# Release build (distribution certificate)
xcodebuild -project SLATE.xcodeproj \
           -scheme SLATE \
           -configuration Release \
           clean build
```

### CI/CD Builds

The GitHub Actions workflow automatically handles code signing:

1. **Secrets Required** (in GitHub repository settings):
   - `APPLE_ID`: Apple ID email
   - `APPLE_ID_PASSWORD`: App-specific password
   - `APPLE_TEAM_ID`: Your 10-character Team ID

2. **Process**:
   - Builds with distribution certificate
   - Notarizes with Apple's notary service
   - Staples notarization ticket
   - Creates distributable DMG

## Notarization Process

### Manual Notarization

```bash
# 1. Create DMG
hdiutil create -volname "SLATE" \
             -srcfolder "build/Release/SLATE.app" \
             -ov -format UDZO \
             "SLATE.dmg"

# 2. Upload for notarization
xcrun notarytool submit \
    --apple-id "your@email.com" \
    --password "app-specific-password" \
    --team-id "YOUR_TEAM_ID" \
    --wait \
    SLATE.dmg

# 3. Staple the ticket
xcrun stapler staple SLATE.dmg

# 4. Verify
xcrun stapler validate SLATE.dmg
```

### Automated Notarization

The CI pipeline handles this automatically with:
- `notarytool` for submission
- Automatic waiting for completion
- Stapling to the application
- Validation of the result

## Troubleshooting

### Common Issues

1. **"Certificate revoked" or "expired"**
   - Check certificate validity in Keychain Access
   - Renew through Apple Developer portal
   - Download and reinstall

2. **"No provisioning profile found"**
   - Clean build folder: `xcodebuild clean`
   - Re-select team in Xcode settings
   - Manually download provisioning profile

3. **"Notarization failed"**
   - Check notarization log:
     ```bash
     xcrun notarytool log <request-uuid>
     ```
   - Common failures:
     - Missing entitlements
     - Hardcoded paths
     - Insecure libraries

4. **"Gatekeeper blocks app"**
   - Verify notarization: `xcrun stapler validate SLATE.app`
   - Check spctl assessment:
     ```bash
     spctl -a -v SLATE.app
     ```

### Debug Commands

```bash
# Check code signature
codesign -dv --verbose=4 SLATE.app

# Verify entitlements
codesign -d --entitlements - SLATE.app

# Check notarization status
xcrun stapler validate -v SLATE.app

# Run Gatekeeper assessment
spctl -a -v --type exec SLATE.app
```

## Security Best Practices

1. **Certificate Management**
   - Store private keys securely
   - Use different certificates for dev/prod
   - Monitor certificate expiration

2. **Entitlements**
   - Request minimum necessary permissions
   - Document why each entitlement is needed
   - Review regularly for unused entitlements

3. **Distribution**
   - Always notarize before distribution
   - Include DMG with application
   - Provide checksum verification

## Maintenance

### Annual Tasks

1. **Renew Certificates** (before expiration)
   - Development certificates: 1 year
   - Distribution certificates: 1 year
   - Provisioning profiles: 1 year

2. **Update Team Information**
   - Check Apple Developer portal
   - Update contact information
   - Verify team membership

### Version Updates

When updating macOS target:
1. Check for new entitlement requirements
2. Update deployment target in Xcode
3. Test on oldest supported macOS version

## Distribution Checklist

Before releasing:

- [ ] Code signed with distribution certificate
- [ ] Notarization successful
- [ ] Stapling complete
- [ ] DMG created and tested
- [ ] Gatekeeper passes
- [ ] Checksum generated
- [ ] Version number updated
- [ ] Release notes prepared

## References

- [Apple Code Signing Guide](https://developer.apple.com/documentation/xcode/code-signing)
- [Notarizing macOS Apps](https://developer.apple.com/documentation/xcode/notarizing_macos_apps_before_distribution)
- [App Sandbox Design Guide](https://developer.apple.com/documentation/security/app_sandbox)
