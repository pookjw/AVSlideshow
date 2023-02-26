//
//  PhotosViewModel.swift
//  AVSlideshow_iOS
//
//  Created by Jinwoo Kim on 2/25/23.
//

@preconcurrency import UIKit
@preconcurrency import Photos
@preconcurrency import Combine

actor PhotosViewModel: NSObject {
    enum Error: Swift.Error {
        case cannotAccessPhotoLibrary
    }
    
    let collectionsSubject: CurrentValueSubject<[PHAssetCollectionType : [PHAssetCollection]]?, Swift.Error> = .init(nil)
    let selectedCollectionSubject: CurrentValueSubject<PHAssetCollection?, Never> = .init(nil)
    
    private let dataSoure: UICollectionViewDiffableDataSource<PhotosSectionModel, PhotosItemModel>
    private var imageAssets: PHFetchResult<PHAsset>?
    private var selectedCollectionAssets: PHFetchResult<PHAsset>?
    private var smartAlbumCollections: PHFetchResult<PHAssetCollection>?
    private var albumCollections: PHFetchResult<PHAssetCollection>?
    
    init(dataSoure: UICollectionViewDiffableDataSource<PhotosSectionModel, PhotosItemModel>) {
        self.dataSoure = dataSoure
        super.init()
        PHPhotoLibrary.shared().register(self)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    func loadDataSource() async throws {
        try await requestAuthorization()
        
        let imageOptions: PHFetchOptions = .init()
        imageOptions.sortDescriptors = [.init(key: #keyPath(PHAsset.creationDate), ascending: false)]
        
        let imageAssets: PHFetchResult<PHAsset> = PHAsset.fetchAssets(with: .image, options: imageOptions)
        self.imageAssets = imageAssets
        
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
        albumOptions.sortDescriptors = [.init(key: #keyPath(PHAssetCollection.startDate), ascending: true)]
        
        let smartAlbumCollections: PHFetchResult<PHAssetCollection> = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: albumOptions)
        self.smartAlbumCollections = smartAlbumCollections
        
        let albumCollections: PHFetchResult<PHAssetCollection> = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: albumOptions)
        self.albumCollections = albumCollections
        
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
        
        let imageOptions: PHFetchOptions = .init()
        imageOptions.sortDescriptors = [.init(key: #keyPath(PHAsset.creationDate), ascending: false)]
        
        if let collection: PHAssetCollection {
            imageAssets = PHAsset.fetchAssets(in: collection, options: imageOptions)
            self.imageAssets = imageAssets
            self.selectedCollectionAssets = nil
        } else {
            imageAssets = PHAsset.fetchAssets(with: .image, options: imageOptions)
            self.imageAssets = nil
            self.selectedCollectionAssets = imageAssets
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
    
    private func updateDataSource(for changeInstance: PHChange) async {
        let updateAssetsHandler: @Sendable (PHFetchResultChangeDetails<PHAsset>) async -> Void = { [dataSoure] changeDetails in
            var snapshot: NSDiffableDataSourceSnapshot<PhotosSectionModel, PhotosItemModel> = dataSoure.snapshot()
            
            guard let sectionModel: PhotosSectionModel = snapshot.sectionIdentifiers.first(where: { $0.sectionType == .images }) else {
                return
            }
            
            if
                let removedItemModels: [PhotosItemModel] = changeDetails
                    .removedIndexes?
                    .sorted(by: >)
                    .map({ removedObjectIndex in
                        let itemModel: PhotosItemModel = snapshot.itemIdentifiers(inSection: sectionModel)[removedObjectIndex]
                        return itemModel
                    })
            {
                snapshot.deleteItems(removedItemModels)
            }
            
            let countOfItemModels: Int = snapshot.numberOfItems(inSection: sectionModel)
            changeDetails
                .insertedIndexes?
                .enumerated()
                .forEach { index, insertedObjectIndex in
                    let asset: PHAsset = changeDetails.insertedObjects[index]
                    let itemModel: PhotosItemModel = .init(asset: asset)
                    
                    if (countOfItemModels == .zero) && (countOfItemModels == insertedObjectIndex + 1) {
                        snapshot.appendItems([itemModel], toSection: sectionModel)
                    } else {
                        let beforeItemModel: PhotosItemModel = snapshot.itemIdentifiers(inSection: sectionModel)[insertedObjectIndex]
                        snapshot.insertItems([itemModel], beforeItem: beforeItemModel)
                    }
                }
            
            if
                let changeDetails: [PhotosItemModel] = changeDetails
                    .changedIndexes?
                    .map({ changedObjectIndex in
                        let itemModel: PhotosItemModel = snapshot.itemIdentifiers(inSection: sectionModel)[changedObjectIndex]
                        return itemModel
                    })
            {
                snapshot.reconfigureItems(changeDetails)
            }
                
            changeDetails
                .enumerateMoves { fromIndex, toIndex in
                    let itemModels: [PhotosItemModel] = snapshot.itemIdentifiers(inSection: sectionModel)
                    let fromItemModel: PhotosItemModel = itemModels[fromIndex]
                    let toItemModel: PhotosItemModel = itemModels[toIndex]
                    
                    if fromIndex < toIndex {
                        let beforeToItemModel: PhotosItemModel = itemModels[toIndex - 1]
                        snapshot.moveItem(toItemModel, afterItem: fromItemModel)
                        snapshot.moveItem(fromItemModel, afterItem: beforeToItemModel)
                    } else {
                        let beforeFromItemModel: PhotosItemModel = itemModels[toIndex - 1]
                        snapshot.moveItem(fromItemModel, afterItem: toItemModel)
                        snapshot.moveItem(toItemModel, afterItem: beforeFromItemModel)
                    }
                }
            
            await dataSoure.apply(snapshot, animatingDifferences: true)
        }
        
        if 
            let selectedCollectionAssets: PHFetchResult<PHAsset>,
            let changeDetails: PHFetchResultChangeDetails<PHAsset> = changeInstance.changeDetails(for: selectedCollectionAssets),
            changeDetails.hasIncrementalChanges
        {
            await updateAssetsHandler(changeDetails)
            self.selectedCollectionAssets = changeDetails.fetchResultAfterChanges
        } else if
            let imageAssets: PHFetchResult<PHAsset>,
            let changeDetails: PHFetchResultChangeDetails<PHAsset> = changeInstance.changeDetails(for: imageAssets),
            changeDetails.hasIncrementalChanges
        {
            await updateAssetsHandler(changeDetails)
            self.imageAssets = changeDetails.fetchResultAfterChanges
        }
        
        //
        
        if 
            let selectedCollection: PHAssetCollection = selectedCollectionSubject.value,
            let changeDetails: PHObjectChangeDetails<PHAssetCollection> = changeInstance.changeDetails(for: selectedCollection),
            let objectAfterChanges: PHAssetCollection = changeDetails.objectAfterChanges
        {
            selectedCollectionSubject.send(objectAfterChanges)
        }
        
        //
        
        var collections: [PHAssetCollectionType : [PHAssetCollection]] = collectionsSubject.value ?? [:]
        var isChanged: Bool = false
        let updateCollectionsHandler: @Sendable ([PHAssetCollection], PHFetchResultChangeDetails<PHAssetCollection>) -> [PHAssetCollection] = { oldCollections, changeDetails in
            var newCollections: [PHAssetCollection] = oldCollections
            
            changeDetails
                .removedIndexes?
                .sorted(by: >)
                .forEach { removedObjectIndex in
                    newCollections.remove(at: removedObjectIndex)
                }
            
            changeDetails
                .insertedIndexes?
                .enumerated()
                .forEach { index, insertedObjectIndex in
                    newCollections.insert(changeDetails.insertedObjects[index], at: insertedObjectIndex)
                }
            
            changeDetails
                .changedIndexes?
                .enumerated()
                .forEach { index, changedObjectIndex in
                    newCollections.remove(at: changedObjectIndex)
                    newCollections.insert(changeDetails.changedObjects[index], at: changedObjectIndex)
                }
            
            changeDetails
                .enumerateMoves { fromIndex, toIndex in
                    newCollections.swapAt(fromIndex, toIndex)
                }
            
            return newCollections
        }
        
        if
            let smartAlbumCollections: PHFetchResult<PHAssetCollection>,
            let changeDtails: PHFetchResultChangeDetails<PHAssetCollection> = changeInstance.changeDetails(for: smartAlbumCollections),
            changeDtails.hasIncrementalChanges
        {
            let oldCollections: [PHAssetCollection] = collections[.smartAlbum] ?? .init()
            collections[.smartAlbum] = updateCollectionsHandler(oldCollections, changeDtails)
            isChanged = true
            self.smartAlbumCollections = changeDtails.fetchResultAfterChanges
        }
        
        if
            let albumCollections: PHFetchResult<PHAssetCollection>,
            let changeDtails: PHFetchResultChangeDetails<PHAssetCollection> = changeInstance.changeDetails(for: albumCollections),
            changeDtails.hasIncrementalChanges
        {
            let oldCollections: [PHAssetCollection] = collections[.album] ?? .init()
            collections[.album] = updateCollectionsHandler(oldCollections, changeDtails)
            isChanged = true
            self.albumCollections = changeDtails.fetchResultAfterChanges
        }
        
        if isChanged {
            collectionsSubject.send(collections)
        }
    }
}

extension PhotosViewModel: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task {
            await updateDataSource(for: changeInstance)
        }
    }
}
