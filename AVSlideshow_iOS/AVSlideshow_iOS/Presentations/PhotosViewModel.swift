//
//  PhotosViewModel.swift
//  AVSlideshow_iOS
//
//  Created by Jinwoo Kim on 2/25/23.
//

import UIKit
@preconcurrency import Photos
@preconcurrency import Combine

actor PhotosViewModel {
    enum Error: Swift.Error {
        case cannotAccessPhotoLibrary
    }
    
    let collectionsSubject: CurrentValueSubject<[PHAssetCollectionType : [PHAssetCollection]]?, Swift.Error> = .init(nil)
    let selectedCollectionSubject: CurrentValueSubject<PHAssetCollection?, Never> = .init(nil)
    
    private let dataSoure: UICollectionViewDiffableDataSource<PhotosSectionModel, PhotosItemModel>
    
    init(dataSoure: UICollectionViewDiffableDataSource<PhotosSectionModel, PhotosItemModel>) {
        self.dataSoure = dataSoure
    }
    
    func loadDataSource() async throws {
        try await requestAuthorization()
        
        let imageOptions: PHFetchOptions = .init()
        imageOptions.sortDescriptors = [.init(key: #keyPath(PHAsset.creationDate), ascending: false)]
        
        let imageAssets: PHFetchResult<PHAsset> = PHAsset.fetchAssets(with: .image, options: imageOptions)
        var snapshot: NSDiffableDataSourceSnapshot<PhotosSectionModel, PhotosItemModel> = .init()
        let sectionModel: PhotosSectionModel = .init(sectionType: .images)
        
        snapshot.appendSections([sectionModel])
        
        imageAssets.enumerateObjects { asset, index, stopPointer in
            let itemModel: PhotosItemModel = .init(asset: asset)
            snapshot.appendItems([itemModel], toSection: sectionModel)
        }
        
        await dataSoure.apply(snapshot, animatingDifferences: true)
        
        //
        
        let albumOptions: PHFetchOptions = .init()
        albumOptions.sortDescriptors = [.init(key: #keyPath(PHAssetCollection.localizedTitle), ascending: true)]
        
        let smartAlbumCollections: PHFetchResult<PHAssetCollection> = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: albumOptions)
        let albumCollections: PHFetchResult<PHAssetCollection> = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: albumOptions)
        
        var results: [PHAssetCollectionType : [PHAssetCollection]] = [:]
        
        if smartAlbumCollections.count > .zero {
            var smartAlbumCollectionArray: [PHAssetCollection] = .init()
            
            smartAlbumCollections
                .enumerateObjects { collection, index, stopPointer in
                    smartAlbumCollectionArray.append(collection)
                }
            
            results[.smartAlbum] = smartAlbumCollectionArray
        }
        
        if albumCollections.count > .zero {
            var albumCollectionArray: [PHAssetCollection] = .init()
            
            albumCollections
                .enumerateObjects { collection, index, stopPointer in
                    albumCollectionArray.append(collection)
                }
            
            results[.album] = albumCollectionArray
        }
        
        collectionsSubject.send(results)
    }
    
    func select(collection: PHAssetCollection?) async {
        let imageAssets: PHFetchResult<PHAsset>
        
        if let collection: PHAssetCollection {
            imageAssets = PHAsset.fetchAssets(in: collection, options: nil)
        } else {
            imageAssets = PHAsset.fetchAssets(with: .image, options: nil)
        }
        
        var snapshot: NSDiffableDataSourceSnapshot<PhotosSectionModel, PhotosItemModel> = .init()
        let sectionModel: PhotosSectionModel = .init(sectionType: .images)
        
        snapshot.appendSections([sectionModel])
        
        imageAssets.enumerateObjects { asset, index, stopPointer in
            let itemModel: PhotosItemModel = .init(asset: asset)
            snapshot.appendItems([itemModel], toSection: sectionModel)
        }
        
        await dataSoure.apply(snapshot, animatingDifferences: true)
        selectedCollectionSubject.send(collection)
    }
    
    private func requestAuthorization(authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)) async throws {
        
        switch authorizationStatus {
        case .notDetermined:
            let requestedAuthorizationStatus: PHAuthorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            
            try await requestAuthorization(authorizationStatus: requestedAuthorizationStatus)
        case .restricted, .denied:
            throw Error.cannotAccessPhotoLibrary
        case .authorized, .limited:
            return
        @unknown default:
            throw Error.cannotAccessPhotoLibrary
        }
    }
}
