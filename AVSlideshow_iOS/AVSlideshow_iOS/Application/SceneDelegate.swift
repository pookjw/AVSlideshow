//
//  SceneDelegate.swift
//  AVSlideshow_iOS
//
//  Created by Jinwoo Kim on 2/25/23.
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene: UIWindowScene = scene as? UIWindowScene else { 
            return
        }
        
        let window: UIWindow = .init(windowScene: windowScene)
        let photosViewController: PhotosViewController = .init()
        let navigationController: UINavigationController = .init(rootViewController: photosViewController)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        
        self.window = window
    }
}
