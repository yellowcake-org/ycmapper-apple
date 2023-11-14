//
//  Application.swift
//  ycmapper
//
//  Created by Alexander Orlov on 14.11.2023.
//

import SwiftUI

@main
struct ycmapper: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear(perform: {
                    let status = yc_vid_view_initialize(
                        .none,
                        .none,
                        .none,
                        .none
                    )

                    debugPrint("status == \(status)")
            })
        }
    }
}
