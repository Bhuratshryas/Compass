//
//  PrivacyPolicyView.swift
//  Compass
//

import SwiftUI

struct PrivacyPolicyView: View {
    private let policyText: String = """
    **Compass – Privacy Policy**

    **Last updated:** 2026

    **We do not collect your data**
    Compass does **not** collect, store, or transmit any of your personal data to our servers or any third party.

    **What happens on your device**
    - **Chat:** Your messages and answers are processed on your device. We do not send your chat content to any server.
    - **Images & OCR:** If you share an image, the text is extracted using Apple’s on-device OCR. No image text is sent to any external service.
    - **Your content:** Conversations are stored only on your device in the app’s local storage. We have no access.
    - **No analytics or tracking:** We do not use analytics, advertising, or tracking. We do not collect device identifiers or usage data.

    **Permissions we use**
    - **Photo Library:** Only if you choose to attach an image. Access is limited to the photos you select; we do not collect or upload them.

    **Changes to this policy**
    If we ever change this policy, we will update this page and the “Last updated” date.
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(policyText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(CompassTheme.textPrimary)
                    .padding(CompassTheme.paddingH)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .background(CompassTheme.background.ignoresSafeArea())
        }
    }
}

