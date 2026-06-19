//
//  ContentView.swift
//  BulkReadGmailForiOS
//
//  Created by 飯田泰智 on 2026/06/18.
//

import SwiftUI

struct ContentView: View {
    @State private var authManager = AuthManager()

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainView()
                    .environment(authManager)
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity))
            } else {
                LoginView()
                    .environment(authManager)
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity))
            }
        }
    }
}

#Preview {
    ContentView()
}
