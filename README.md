# Compass

A professional privacy-first on-device assistant. Ask questions, attach images, and get helpful responses with everything processed locally (no data collection, no analytics, no cloud transmission).

## Features

- On-device chat and search
- Image understanding using on-device OCR
- Apple Intelligence support when available (fallback to local frameworks otherwise)
- Clean, professional Apple-style UI

## What happens on your device

- **Chat:** Your text questions are processed on-device.
- **OCR (images):** If you attach an image, its text is extracted using Apple’s on-device OCR. No image/OCR text is sent to external services.
- **Storage:** Conversations are saved locally in the app. We have no access.
- **No analytics or tracking:** Compass does not use analytics, advertising, or tracking.

## Privacy Policy

**We do not collect your data.** Compass does **not** collect, store, or transmit any of your personal data to our servers or any third party.

### What happens on your device

- **Chat:** Your questions and the assistant’s answers are processed on your device. We do not send your chat content to any external server.
- **Images & OCR:** When you attach an image, Compass uses Apple’s on-device Vision/OCR APIs to read text from the image. The image and extracted text stay on your device and are not uploaded to us or any third party.
- **Conversations:** Your conversations are stored only in the app’s local storage on your device. We do not operate any backend service that can access them.
- **No analytics or tracking:** Compass does not use analytics, advertising, or tracking SDKs. We do not collect device identifiers, usage statistics, or any other telemetry.

### Permissions we use

- **Photo Library:** Used only when you choose to attach an image. Access is limited to the photos you select; we do not collect or upload them.

### Changes to this policy

If we change this policy (for example, to describe new features), we will update this page and the “Last updated” date in the app’s Privacy Policy screen.

### Contact

If you have questions about privacy or this policy, contact us using the support email listed on the Compass App Store page.

## Requirements

- iOS 16+ (iOS 26 recommended for Apple Intelligence / Foundation Models)
- Xcode 16+ (for the iOS 26 SDK + Foundation Models)

## Setup

1. Open the `Compass.xcodeproj` in Xcode.
2. Select your development team under Signing & Capabilities.
3. Build and run on a device (recommended).

## Contact

If you have questions about privacy, use the support email you list in your App Store listing.

