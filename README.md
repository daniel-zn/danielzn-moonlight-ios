# Moonlight iOS/tvOS

[![CI](https://github.com/moonlight-stream/moonlight-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/moonlight-stream/moonlight-ios/actions/workflows/ci.yml)

[Moonlight for iOS/tvOS](https://moonlight-stream.org) is an open source client for [Sunshine](https://github.com/LizardByte/Sunshine) and NVIDIA GameStream. Moonlight for iOS/tvOS allows you to stream your full collection of games and apps from your powerful desktop computer to your iOS device or Apple TV.

Moonlight also has a [PC client](https://github.com/moonlight-stream/moonlight-qt) and [Android client](https://github.com/moonlight-stream/moonlight-android).

Check out [the Moonlight wiki](https://github.com/moonlight-stream/moonlight-docs/wiki) for more detailed project information, setup guide, or troubleshooting steps.

[![Moonlight for iOS and tvOS](https://moonlight-stream.org/images/App_Store_Badge_135x40.svg)](https://apps.apple.com/us/app/moonlight-game-streaming/id1000551566)

## About this fork

> [!NOTE]
> This is a personal fork (`daniel-zn/danielzn-moonlight-ios`, default branch `main`), an iPhone app called
> **Artemis**, made to pair with [daniel-zn/danielzn-Apollo](https://github.com/daniel-zn/danielzn-Apollo) and to
> match the macOS client in [daniel-zn/danielzn-moonlight-qt](https://github.com/daniel-zn/danielzn-moonlight-qt).
> It doesn't follow upstream updates. It's not affiliated with Moonlight, nor with the Artemis Android client.

Changes from upstream so far:

- Named Artemis (bundle `com.danielzn.artemis`), iPhone only, iOS 26 or later. The Xcode target, the built
  `Moonlight.app` and the code keep upstream's names. No Apple TV target.
- A native SwiftUI interface with Liquid Glass (`Artemis/`), in the macOS client's screens, worded for a remote
  desktop rather than games: Computers (a row per PC with its status: tap to open its apps, pair or wake it), the
  pairing PIN, Apps (artwork, an Active badge, Resume and Stop), and Settings in the Mac's sections.
- Touch controls for the remote desktop (`Artemis/Desktop/`, spec in [docs/TOUCH.md](docs/TOUCH.md)): trackpad and
  direct modes, clicks, drags, two-finger scrolling, pinch to zoom, a movable Liquid Glass control bar, the keyboard
  with a key row (Esc, Tab, sticky Ctrl/Alt/Win/Shift, arrows, F1–F12; Fn pinned while the keys scroll; swipe the
  row down to close the keyboard) and Windows shortcuts. Upright (the desktop on
  top, a trackpad under it) or landscape (full screen).
- The UI font is [Orbix](https://fontesk.com/orbix-font/) by Besign Foundry (`Artemis/Fonts/`, SIL Open Font License
  1.1, `OFL.txt`), with SF Pro for digits and the characters it lacks. It replaces the storyboards, `MainFrameViewController`, the settings screen and `SWRevealViewController`:
  their logic is in `Artemis/Model/ComputerStore.swift` and `Artemis/Bridge/ArtemisBridge.m`. The streaming core
  (`Limelight/Stream`, `Limelight/Input`, `StreamFrameViewController`) is upstream's, presented full screen.
- A new app icon (`Artemis/AppIcon.icon`, Icon Composer).
- UI tests with screenshots of every screen (`ArtemisUITests`, `Scripts/ui-tests.sh`): upright and landscape,
  default and largest accessibility text, light and dark, against stand-in PCs (`-ArtemisDemo YES`), where
  connecting opens a picture of a desktop that records the input each gesture sends (`DesktopTests`).
- Uses the scene lifecycle (`Artemis/App/SceneDelegate.swift`): apps built with the iOS 27 SDK that don't are ended at
  launch.
- Tapping an asleep PC wakes it (Wake-on-LAN), shows "Waking up…" and opens it once it's up; the status follows
  discovery's polls (`ArtemisHostUpdatedNotification`), and a PC that doesn't come up in 90 s goes back to Offline
  with "Couldn't Wake <PC>". See [Waking a PC](#waking-a-pc).
- A PC this iPhone paired with stays paired while it's asleep, waking up or out of reach: only its own HTTPS answer
  (with the certificate pinned at pairing) can say it isn't. Plain HTTP answers always say "not paired" and hide the
  MAC address, so they don't count for it (`DiscoveryWorker acceptResponse:`), unless the PC keeps refusing this
  iPhone for 30 s (Apollo reinstalled or the iPhone removed there), when it shows "Not paired" to pair again.
- The Mac app's PC and app actions: Rename…, Get Info, Connect Automatically When Opening PC, Stop the app on the PC
  after a session, and the rest compared in [docs/PARITY.md](docs/PARITY.md).
- Game controllers: passed to the PC as gamepads (upstream's ControllerSupport, without the on-screen gamepad), or
  the PC's mouse while Start / Menu is held for a moment (`Artemis/Desktop/GamepadMouse.swift`, docs/TOUCH.md).
- In the Games category (App Store Connect and `LSApplicationCategoryType`), with Game Mode (`GCSupportsGameMode`)
  and extended-gamepad support declared, so the App Store build shows in Apple's Games app.
- `Scripts/testflight.sh` and `Scripts/asc.py` upload builds to TestFlight (internal testing only).
- Build from the command line with `-scmProvider system`. If Xcode's own package download hangs on the OpenSSL
  binary, download its zip once into `~/Library/Caches/org.swift.swiftpm/artifacts/` under the URL-derived name
  SwiftPM uses (`https___github_com_krzyzanowskim_OpenSSL_releases_download_<version>_OpenSSL_xcframework_zip`).

Planned: microphone passthrough to Apollo (as in the macOS client).

## Waking a PC

Wake-on-LAN sends the magic packet for the PC's MAC address (`Limelight/Network/WakeOnLanManager.m`), three
times, on ports 9, 7, 47009 and Moonlight's ports:

- **Unicast** to every address Artemis knows for the PC (its LAN address, the active, manual, external and IPv6
  ones). It reaches a sleeping PC whose network adapter answers ARP for it (Windows' ARP offload; Enchilada's Intel
  I219-V has it on, with Wake on Magic Packet) or whose address the iPhone still has cached.
- **Broadcast** to 255.255.255.255 and each local network's broadcast address. Since iOS 14.5 that needs the
  restricted entitlement `com.apple.developer.networking.multicast`; without it `sendto()` fails and the log says
  so ("iOS blocks broadcasts without the … entitlement").

Artemis doesn't have the entitlement yet. `Signing/Artemis.entitlements` has it, ready, but it isn't used: signing
fails until Apple grants it for the team. Once Apple approves the request (made at
https://developer.apple.com/contact/request/networking-multicast, for bundle `com.danielzn.artemis`), switching it on
takes two minutes:

1. developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → `com.danielzn.artemis` → Additional
   Capabilities → tick **Multicast Networking** → Save. (This invalidates the "Artemis App Store" profile.)
2. Make the profile again with the capability in it: `mercurius-agent secret run --env ASC_KEY_ID,ASC_ISSUER_ID,ASC_KEY_P8 -- Scripts/asc.py profile`.
3. Ship with it: `ARTEMIS_MULTICAST=1 Scripts/testflight.sh` (it signs with `Signing/Artemis.entitlements` and
   checks the entitlement is in the signed app; `--validate-only` first to try it without uploading). To keep it
   on, make `ARTEMIS_MULTICAST` default to 1 in `Scripts/testflight.sh` and set `CODE_SIGN_ENTITLEMENTS =
   Signing/Artemis.entitlements` on the Moonlight target.

## Building
* Install Xcode from the [App Store page](https://apps.apple.com/us/app/xcode/id497799835)
* Run `git clone --recursive https://github.com/moonlight-stream/moonlight-ios.git`
  *  If you've already clone the repo without `--recursive`, run `git submodule update --init --recursive`
* Open Moonlight.xcodeproj in Xcode
* To run on a real device, you will need to locally modify the signing options:
    * Click on "Moonlight" at the top of the left sidebar
    * Click on the "Signing & Capabilities" tab
    * Under "Targets", select "Moonlight"
    * In the "Team" dropdown, select your name. If your name doesn't appear, you may need to sign into Xcode with your Apple account.
    * Change the "Bundle Identifier" to something different. You can add your name or some random letters to make it unique.
    * Now you can select your Apple device in the top bar as a target and click the Play button to run.
