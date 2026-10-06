<p align="center">
  <img src="StatalePlus/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" alt="Statale Plus">
</p>

<h1 align="center">Statale Plus</h1>

<p align="center">
  <b>Everything a student of the University of Milan needs, in one native iOS app.</b><br>
  Timetable, exams, attendance and course sites — plus lecture recordings with on-device transcription and AI summaries.
</p>

<p align="center">
  <a href="https://github.com/mattmeligeni/StatalePlus/actions/workflows/compila.yml"><img src="https://github.com/mattmeligeni/StatalePlus/actions/workflows/compila.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/version-1.0%20%E2%80%A2%20build%203-informational" alt="Version 1.0, build 3">
  <img src="https://img.shields.io/badge/iOS-26%2B-black?logo=apple" alt="iOS 26+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/Xcode-27-147EFB?logo=xcode&logoColor=white" alt="Xcode 27">
  <img src="https://img.shields.io/badge/UI-SwiftUI-0A84FF" alt="SwiftUI">
  <img src="https://img.shields.io/badge/TestFlight-beta-0D96F6?logo=apple&logoColor=white" alt="TestFlight beta">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-PolyForm%20Strict%201.0.0-lightgrey" alt="License: PolyForm Strict 1.0.0"></a>
</p>

<p align="center"><b>English</b> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> Statale Plus is an **independent, unofficial** project. It is not affiliated with, sponsored by or endorsed by the
> Università degli Studi di Milano. Screenshots show the built-in demo mode with fictional data.

## Screenshots

<table>
  <tr>
    <td align="center"><img src="Grafica/Screenshot/oggi.png" width="200" alt="Today"><br><sub>Today</sub></td>
    <td align="center"><img src="Grafica/Screenshot/orario.png" width="200" alt="Timetable"><br><sub>Timetable</sub></td>
    <td align="center"><img src="Grafica/Screenshot/ariel.png" width="200" alt="Ariel course sites"><br><sub>Ariel course sites</sub></td>
    <td align="center"><img src="Grafica/Screenshot/esami.png" width="200" alt="Exam calendar"><br><sub>Exam calendar</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="Grafica/Screenshot/presenze.png" width="200" alt="Attendance"><br><sub>Attendance</sub></td>
    <td align="center"><img src="Grafica/Screenshot/registrazioni.png" width="200" alt="Lecture recordings"><br><sub>Lecture recordings</sub></td>
    <td align="center"><img src="Grafica/Screenshot/riassunto.png" width="200" alt="AI summary of a lecture"><br><sub>AI summary of a lecture</sub></td>
    <td align="center"><img src="Grafica/Screenshot/ia.png" width="200" alt="On-device AI settings"><br><sub>On-device AI settings</sub></td>
  </tr>
</table>

<p align="center"><img src="Grafica/Screenshot/oggi-scuro.png" width="200" alt="Today, dark mode"><br><sub>Dark mode</sub></p>

## Features

- **One sign-in** for the university services that today live in four different systems (UNIMIA, SIFA, Ariel/myAriel
  and the timetable APIs), with credentials stored only in the iOS Keychain.
- **Today** — the day's lectures with room and time, the lecture in progress, your next booked exam and Ariel notices.
- **Timetable** — your course schedule by week and semester, plus free classrooms.
- **Exams** — exam calendar, bookings, transcript of records and fees.
- **Attendance** — check in with the lecture code or QR code and track attendance against your course requirements.
- **Ariel** — course sites, materials, forums and deadlines, read and shown natively.
- **Lecture recordings**
  - records with the screen locked, with bookmarks and audio enhancement for listening;
  - **transcription on the device**: Apple Speech or NVIDIA **Parakeet** (optional 632 MB download, more accurate,
    keeps working in the background);
  - **summaries with Apple Intelligence**: key points and review questions, written from the transcript only;
  - a **course glossary** that fixes technical terms mangled by speech recognition and **learns from your lectures**;
  - export all recordings to one archive and import it on another iPhone straight from the Share menu.
- **Demo mode** for reviewers and anyone without a university account.

## Privacy

- Audio and transcripts never leave the iPhone. Summaries run on the device with Apple Intelligence; the online
  model (Apple Private Cloud Compute) will be optional, once Apple enables it for the app.
- No accounts, no analytics, no tracking, no third-party SDKs. The app talks only to the university's services.
- Credentials live in the Keychain and are used only to sign in to the university's own systems.

## Requirements

- iPhone with **iOS 26** or later (iPhone 11 and newer).
- Summaries and the course glossary need **Apple Intelligence** (iPhone 15 Pro and newer).

## Try it

- **TestFlight**: a public beta is coming soon.
- **Build it yourself** (for personal, non-commercial use — see the license):
  1. Xcode 27, then open `StatalePlus.xcodeproj`;
  2. in *Signing & Capabilities* choose your own team (local change only);
  3. run on a simulator or device. To explore without a university account, sign in with the demo credentials in
     the *Versione dimostrativa* section of the [Italian documentation](README.it.md#versione-dimostrativa).

  From the command line:

  ```bash
  xcodebuild -project StatalePlus.xcodeproj -scheme StatalePlus -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
  ```

## Documentation

The full technical documentation — features in detail, architecture, authentication, endpoints, data formats,
persistence — is in Italian: **[README.it.md › Documentazione tecnica](README.it.md#documentazione-tecnica)**.
Release notes: [CHANGELOG.md](CHANGELOG.md).

## Contributing

Bug reports and ideas are welcome through GitHub issues (please never include real personal data). Pull requests
are accepted under the contributor agreement in [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: see
[SECURITY.md](SECURITY.md).

## License

Statale Plus is **source-available, not open source**: [PolyForm Strict License 1.0.0](LICENSE) with the
[additional permissions](ADDITIONAL-PERMISSIONS.md) to build it locally and to contribute.

- ✅ Read the code, build it and run it on your own devices for non-commercial purposes; propose contributions.
- ❌ Redistribute it in any form (App Store, TestFlight, other stores or websites), publish apps or services based on
  it, or use it commercially — without written permission.
- The name "Statale Plus" and its icon are reserved.

Third-party components keep their own licenses — see [NOTICE](NOTICE): [FluidAudio](https://github.com/FluidInference/FluidAudio)
(Apache 2.0) and the NVIDIA Parakeet model (CC BY 4.0).

---

<sub>© 2026 Mattia Meligeni. Statale Plus is not affiliated with the Università degli Studi di Milano. Data come from
the university's services and may be out of date: the official website always prevails.</sub>
