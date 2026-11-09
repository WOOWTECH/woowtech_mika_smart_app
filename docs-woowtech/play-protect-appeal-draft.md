# Play Protect review draft — not submitted

Status: evidence package prepared; not an assertion that the app is free of security defects. Confirm submission authorization, contact email and VirusTotal upload before filing. Submit the exact artifact hash; do not substitute the signing certificate hash.

## Form fields

- Contact email: **required from owner**
- Developer: WOOW TECH CO., LTD.
- Package: `io.woowtech.agent`
- Artifact: public `0.1.37-woow.4`, versionCode 3804, arm64
- APK SHA-256: `2da75046061ca0f23c94a076b8f405abf1c13554dc46bf789505193afbe13442`
- VirusTotal upload status: **not verified**
- Public APK: https://github.com/WOOWTECH/woowtech_mika_smart_app/releases/download/v0.1.37-woow.4/woowtech-agent-v0.1.37-woow.4-arm64.apk

## Additional information draft

We request review of the Google Play Protect classification of the exact APK identified above. This is a GitHub-distributed Android assistant named 渥屋助理 (woowtech agent).

On a POCO C85 (25078PC3EG), Android 15 / HyperOS 2, opening this officially signed APK through Files and confirming an in-place update produced a harmful-app block. The warning did not identify a specific harmful behavior. APK signature verification and ZIP CRC checks passed. These checks do not establish the absence of harmful behavior; we provide them to identify the reviewed artifact and exclude a damaged package as the explanation.

The certificate SHA-256 is 806b3db808ecbb4d2d032b34624baa7e193802f17a07afbde2a03e78da9474c8. The app provides user-directed phone automation and includes accessibility screen-reading/gesture/screenshot capabilities, a shell helper with authorized elevated access, a sandbox runtime, and optional authenticated computer access. It declares REQUEST_INSTALL_PACKAGES for the system-confirmed updater and WRITE_SECURE_SETTINGS for the authorized helper setup. We disclose these capabilities for review rather than assuming their presence alone explains the classification.

A separately built speech-fix APK with the same package/version and certificate, but a DIFFERENT APK SHA-256 (169407a72c1e5ed22e7218a70b4dccb90cc490e36ff0dc1bf3582c131f8e7d2c), was also scanned through Files on 2026-11-09. Its JIT scan returned POTENTIALLY_UNWANTED with threatType generic_malware and description 此应用可能有害。. This response is evidence for that separate artifact, not a claim that the same internal response was captured for the public APK above. We can identify that artifact separately if filing a second review.

After the second artifact's warning, installation completed only following a recorded user-selection ALLOW event. We do not present that override, nor a successful ADB installation, as a clean Play Protect result. We request review of the specified public artifact's classification based on its actual behavior and the attached evidence.

## Before submission

1. Confirm that the identified public APK was uploaded to VirusTotal and use its exact SHA-256. Public hash lookup has not supplied a verified analysis report.
2. Provide the owner's contact email and authorize the external submission.
3. Include only the APK identity, relevant warning evidence and necessary app explanation. Do not attach full device logcat, remote-access tokens, signing keys, passwords, or unrelated user data.
4. Review compliance and any concrete security findings before asserting the classification is erroneous. This draft does not promise a reversal or response deadline.
