//
//  CrackTheCaseIosApp.swift
//  CrackTheCaseIos
//
//  Created by AFP PAR 049 on 01/07/2026.
//

import SwiftUI

@main
struct CrackTheCaseIosApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Belt-and-suspenders with `Info.plist`'s
                // `UIUserInterfaceStyle: Dark` — this app's whole visual
                // language (`CinematicBackground`, the "Detective Vintage"
                // palette in `Theme.swift`) assumes a dark backdrop
                // everywhere, so it's never meant to adapt to a light
                // system appearance.
                .preferredColorScheme(.dark)
        }
    }
}
