//
//  PhotosViewController.swift
//  AVSlideshow_iOS
//
//  Created by Jinwoo Kim on 2/25/23.
//

@preconcurrency import UIKit
@preconcurrency import Combine
@preconcurrency import Photos

@MainActor final class PhotosViewController: UIViewController {
    private var collectionView: UICollectionView!
    private var albumButton: UIButton!
    private var viewModel: PhotosViewModel!
    private var loadingDataSourceTask: Task<Void, Never>?
    private var collectionsSubjectTask: Task<Void, Never>?
    private var selectedCollectionSubjectTask: Task<Void, Never>?
    
    deinit {
        loadingDataSourceTask?.cancel()
        collectionsSubjectTask?.cancel()
        selectedCollectionSubjectTask?.cancel()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupAlbumButton()
        setupAttributes()
        setupViewModel()
        bind()
        loadDataSource()
    }
    
    private func setupCollectionView() {
        let collectionViewLayout: PhotosCollectionViewLayout = .init()
        let collectionView: UICollectionView = .init(frame: view.bounds, collectionViewLayout: collectionViewLayout)
        
        collectionView.delegate = self
        collectionView.allowsMultipleSelection = true
        
        view.addSubview(collectionView)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        self.collectionView = collectionView
    }
    
    private func setupAlbumButton() {
        let albumButton: UIButton = .init()
        albumButton.showsMenuAsPrimaryAction = true
        self.albumButton = albumButton
    }
    
    private func setupViewModel() {
        let dataSource: UICollectionViewDiffableDataSource<PhotosSectionModel, PhotosItemModel> = makeDataSource()
        let viewModel: PhotosViewModel = .init(dataSoure: dataSource)
        self.viewModel = viewModel
    }
    
    private func setupAttributes() {
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        
        navigationItem.titleView = albumButton
    }
    
    private func bind() {
        let collectionsSubject: CurrentValueSubject<[PHAssetCollectionType : [PHAssetCollection]]?, Swift.Error> = viewModel.collectionsSubject
        collectionsSubjectTask = .detached { [weak self] in
            do {
                for try await collections in collectionsSubject.values {
                    guard let collections: [PHAssetCollectionType : [PHAssetCollection]] else {
                        continue
                    }
                    
                    await self?.reloadAlbumButtonMenu(using: collections)
                }
            } catch {
                fatalError(error.localizedDescription)
            }
        }
        
        let selectedCollectionSubject: AnyPublisher<PHAssetCollection?, Never> = viewModel
            .selectedCollectionSubject
            .dropFirst()
            .eraseToAnyPublisher()
        selectedCollectionSubjectTask = .detached { [weak self] in
            for await selectedCollection in selectedCollectionSubject.values {
                await self?.reloadAlbumButtonMenu(selectedCollection: selectedCollection)
                await self?.updateAlbumButton(isLoading: false)
            }
        }
    }
    
    private func loadDataSource() {
        updateAlbumButton(isLoading: true)
        
        loadingDataSourceTask = .detached { [weak self] in
            do {
                try await self?.viewModel.loadDataSource()
                await MainActor.run { [weak self] in
                    self?.updateAlbumButton(isLoading: false)
                }
            } catch PhotosViewModel.Error.cannotAccessPhotoLibrary {
                await self?.presentAuthorizationErrorAlertController()
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
    
    private func makeDataSource() -> UICollectionViewDiffableDataSource<PhotosSectionModel, PhotosItemModel> {
        let cellRegsitration: UICollectionView.CellRegistration<UICollectionViewListCell, PhotosItemModel> = makeCellRegistration()
        
        let dataSource: UICollectionViewDiffableDataSource<PhotosSectionModel, PhotosItemModel> = .init(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            let cell: UICollectionViewListCell = collectionView.dequeueConfiguredReusableCell(using: cellRegsitration, for: indexPath, item: itemIdentifier)
            return cell
        }
        
        return dataSource
    }
    
    private func makeCellRegistration() -> UICollectionView.CellRegistration<UICollectionViewListCell, PhotosItemModel> {
        .init { cell, indexPath, itemIdentifier in
            let contentConfiguration: PhotosContentConfiguration = .init(asset: itemIdentifier.asset, isSelected: false)
            cell.contentConfiguration = contentConfiguration
            
            cell.configurationUpdateHandler = { cell, state in
                let contentConfiguration: PhotosContentConfiguration = .init(asset: itemIdentifier.asset, isSelected: state.isSelected)
                cell.contentConfiguration = contentConfiguration
            }
        }
    }
    
    private func presentAuthorizationErrorAlertController() {
        let alertController: UIAlertController = .init(title: "ERROR", message: nil, preferredStyle: .alert)
        
        let exitAction: UIAlertAction = .init(title: "Exit", style: .destructive) { _ in
            UIApplication.shared.perform(NSSelectorFromString("suspend"))
            exit(EXIT_FAILURE)
        }
        
        let openSettingsAction: UIAlertAction = .init(title: "Settings", style: .default) { [weak self] _ in
            guard let url: URL = .init(string: UIApplication.openSettingsURLString) else {
                fatalError()
            }
            
            if let windoeScene: UIWindowScene = self?.view.window?.windowScene {
                windoeScene.open(url, options: nil) { _ in
                    exit(EXIT_FAILURE)
                }
            } else {
                UIApplication.shared.open(url) { _ in
                    exit(EXIT_FAILURE)
                }
            }
        }
        
        alertController.addAction(exitAction)
        alertController.addAction(openSettingsAction)
        
        present(alertController, animated: true)
    }
    
    private func reloadAlbumButtonMenu(
        using collections: [PHAssetCollectionType : [PHAssetCollection]]? = nil,
        selectedCollection: PHAssetCollection? = nil
    ) {
        guard let collections: [PHAssetCollectionType : [PHAssetCollection]] = collections ?? viewModel.collectionsSubject.value else {
            return
        }
        
        let selectedCollection: PHAssetCollection? = selectedCollection ?? viewModel.selectedCollectionSubject.value
        
        let buildMenuFromCollection: @MainActor @Sendable ([PHAssetCollection]) -> [UIMenuElement] = { [viewModel, weak self] collections in
            let children: [UIMenuElement] = collections
                .map { collection in
                    let action: UIAction = .init(
                        title: collection.localizedTitle ?? .init(),
                        state: selectedCollection == collection ? .on : .off
                    ) { _ in
                        self?.updateAlbumButton(isLoading: true)
                        
                        Task.detached { [weak self] in
                            await viewModel?.select(collection: collection)
                            await self?.updateAlbumButton(isLoading: false)
                        }
                    }
                    
                    return action
                }
            
            return children
        }
        
        var menuElements: [UIMenuElement] = [
            UIAction(
                title: "All Photos",
                state: selectedCollection == nil ? .on : .off
            ) { [viewModel, weak self] _ in
                self?.updateAlbumButton(isLoading: true)
                
                Task.detached { [weak self] in
                    await viewModel?.select(collection: nil)
                    await self?.updateAlbumButton(isLoading: false)
                }
            }
        ]
        
        if let smartAlbumCollections: [PHAssetCollection] = collections[.smartAlbum] {
            let smartAlbumMenu: UIMenu = .init(
                title: "Smart Album",
                children: buildMenuFromCollection(smartAlbumCollections)
            )
            
            menuElements.append(smartAlbumMenu)
        }
        
        if let albumCollections: [PHAssetCollection] = collections[.album] {
            let albumMenu: UIMenu = .init(
                title: "Album",
                children: buildMenuFromCollection(albumCollections)
            )
            
            menuElements.append(albumMenu)
        }
        
        albumButton.menu = .init(children: menuElements)
    }
    
    private func updateAlbumButton(isLoading: Bool) {
        var configuration: UIButton.Configuration
        
        if isLoading {
            configuration = .plain()
            configuration.showsActivityIndicator = true
        } else {
            configuration = .plain()
            configuration.title = viewModel.selectedCollectionSubject.value?.localizedTitle ?? "All Photos"
            configuration.indicator = .popup
        }
        
        albumButton.configuration = configuration
        albumButton.sizeToFit()
    }
    
    private func exportVideo(indexPaths: [IndexPath]) {
        Task.detached { [weak self] in
            do {
                try await self?.viewModel.exportVideo(indexPaths: indexPaths)
            } catch {
                
            }
        }
    }
}

extension PhotosViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        .init(
            identifier: indexPaths as NSArray
        ) { 
            nil
        } actionProvider: { children in
            var children: [UIMenuElement] = children
            
            let action: UIAction = .init(
                title: "Export as Slideshow",
                image: .init(systemName: "square.and.arrow.up")
            ) { [weak self] _ in
                self?.exportVideo(indexPaths: indexPaths)
            }
            
            children.append(action)
            
            let menu: UIMenu = .init(children: children)
            return menu
        }
    }
}
