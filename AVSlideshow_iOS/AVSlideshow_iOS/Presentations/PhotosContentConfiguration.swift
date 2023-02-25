//
//  PhotosContentConfiguration.swift
//  AVSlideshow_iOS
//
//  Created by Jinwoo Kim on 2/25/23.
//

import UIKit
import Photos

@MainActor struct PhotosContentConfiguration: UIContentConfiguration, Hashable {
    let asset: PHAsset
    
    func makeContentView() -> UIView & UIContentView {
        PhotosContentView(ownConfiguration: self)
    }
    
    func updated(for state: UIConfigurationState) -> PhotosContentConfiguration {
        self
    }
}
