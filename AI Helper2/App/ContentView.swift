//
//  ContentView.swift
//  AI Helper2
//
//  Created by Qinbang Xiao on 28/7/25.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            ChatView()
        } else {
            OnboardingView(isOnboardingComplete: $hasCompletedOnboarding)
        }
    }
}

#Preview {
    ContentView()
}
