//
//  BradburyApp.swift
//  Shared
//
//  Created by Luke Van In on 2022/08/17.
//

import SwiftUI

@main
struct BradburyApp: App {
    
    @ObservedObject var renderController = RenderController()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(renderController)
        }
    }
}
