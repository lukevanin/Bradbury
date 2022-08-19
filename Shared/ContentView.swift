//
//  ContentView.swift
//  Shared
//
//  Created by Luke Van In on 2022/08/17.
//

import SwiftUI
import MetalKit

struct ContentView: View {
    
    @EnvironmentObject var renderController: RenderController
    
    var body: some View {
        ZStack {
            if let image = renderController.image {
                Image(image, scale: 1.0, label: Text("Image"))
                    .background(Color.pink)
                    .frame(width: CGFloat(image.width), height: CGFloat(image.height))
            }
            else {
                ProgressView()
                    .frame(width: 400, height: 400)
            }
        }
        .background(.mint)
        .onAppear {
            renderController.start()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
