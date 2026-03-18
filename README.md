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

Compass does **not** collect, store, or transmit any of your personal data to our servers or any third party.

For the full policy shown in the app, open `Private. On-device only.` and select **Privacy Policy**.

## Requirements

- iOS 16+ (iOS 26 recommended for Apple Intelligence / Foundation Models)
- Xcode 16+ (for the iOS 26 SDK + Foundation Models)

## Setup

1. Open the `Compass.xcodeproj` in Xcode.
2. Select your development team under Signing & Capabilities.
3. Build and run on a device (recommended).

## Contact

If you have questions about privacy, use the support email you list in your App Store listing.

