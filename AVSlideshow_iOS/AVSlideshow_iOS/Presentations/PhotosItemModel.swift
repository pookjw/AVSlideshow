//
//  PhotosItemModel.swift
//  AVSlideshow_iOS
//
//  Created by Jinwoo Kim on 2/25/23.
//

@preconcurrency import Photos

actor PhotosItemModel: Hashable {
    static func == (lhs: PhotosItemModel, rhs: PhotosItemModel) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
    
    let asset: PHAsset
    
    init(asset: PHAsset) {
        self.asset = asset
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(asset)
    }
}
