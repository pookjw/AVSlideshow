//
//  PhotosContentView.swift
//  AVSlideshow_iOS
//
//  Created by Jinwoo Kim on 2/25/23.
//

import UIKit
@preconcurrency import Photos
@preconcurrency import Combine

@MainActor final class PhotosContentView: UIView {
    private var imageView: UIImageView!
    private var progressView: UIProgressView!
    
    private var loadingImageTask: Task<Void, Never>?
    private var currentRequestID: PHImageRequestID?
    
    private var boundsChangesTask: Task<Void?, Never>?
    
    private var ownConfiguration: PhotosContentConfiguration! {
        didSet {
            updateUI()
        }
    }
    
    init(ownConfiguration: PhotosContentConfiguration!) {
        super.init(frame: .null)
        self.ownConfiguration = ownConfiguration
        setupImageView()
        setupProgressView()
        bind()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        loadingImageTask?.cancel()
        boundsChangesTask?.cancel()
    }
    
    private func setupImageView() {
        let imageView: UIImageView = .init()
        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.clipsToBounds = true
        
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        self.imageView = imageView
    }
    
    private func setupProgressView() {
        let progressView: UIProgressView = .init(progressViewStyle: .bar)
        progressView.setProgress(.zero, animated: false)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        
        self.progressView = progressView
    }
    
    private func bind() {
        let stream: AsyncPublisher<AnyPublisher<CGRect, Never>> = publisher(for: \.frame, options: [.new])
            .removeDuplicates()
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
            .values
        
        boundsChangesTask = .detached { [weak self] in
            for await _ in stream {
                await self?.updateUI()
            }
        }
    }
    
    private func updateUI() {
        if let currentRequestID: PHImageRequestID {
            PHImageManager.default().cancelImageRequest(currentRequestID)
        }
        loadingImageTask?.cancel()
        
        progressView.isHidden = false
        progressView.setProgress(.zero, animated: false)
        imageView.isHidden = true
        imageView.image = nil
        
        loadingImageTask = .detached(priority: .high) { [weak self] in
            let options: PHImageRequestOptions = .init()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true
            
            /*
             [weak self]로 capture를 할 경우 block이 불릴 때마다 self가 메모리 상에 살아 있는지 확인하게 될 것이므로 비효율적이다.
             따라서 progressView를 retain해서 capture한다.
             */
            options.progressHandler = { [progressView = await self?.progressView] progress, error, stopPointer, info in
                Task { @MainActor in
                    progressView?.setProgress(Float(progress), animated: false)
                }
            }
            
            guard
                let asset: PHAsset = await self?.ownConfiguration.asset,
                let size: CGSize = await self?.bounds.size
            else {
                return
            }
            
            let result: (image: UIImage?, info: [AnyHashable : Any]?) = await withCheckedContinuation { continuation in
                Task { @MainActor [weak self] in
                    /*
                     `-[PHImageManager cancelImageRequest:]`이 Main Actor에서 호출되고 있고 `currentRequestID` 또한 Main Actor에서 관리되고 있기에 Race Condition을 피하기 위해 Main Actor에서 호출한다.
                     Actor를 별도로 만든다면 Main Actor에서 호출하지 않아도 될 것이다.
                     */
                    self?.currentRequestID = PHImageManager
                        .default()
                        .requestImage(
                            for: asset,
                            targetSize: size,
                            contentMode: .aspectFill,
                            options: options
                        ) { image, options in
                            continuation.resume(with: .success((image, options)))
                        }
                }
            }
            
            if let error: NSError = result.info?[PHImageErrorKey] as? NSError {
                print(error)
                return
            } else if 
                let isCancelled: Bool = result.info?[PHImageCancelledKey] as? Bool,
                isCancelled
            {
                print("Cancelled by PHImageManager.")
                return
            }
            
            guard let image: UIImage = result.image else {
                print("What?")
                return
            }
            
            guard !Task.isCancelled else {
                print("Cancelled by Task.")
                return
            }
            
            await MainActor.run { [weak self] in
                guard !Task.isCancelled else {
                    print("Cancelled by Task.")
                    return
                }
                
                guard let self else { return }
                self.progressView.isHidden = true
                self.imageView.isHidden = false
                self.imageView.image = image
                self.imageView.alpha = .zero
                UIView.animate(withDuration: 0.1) { 
                    self.imageView.alpha = 1.0
                }
            }
        }
    }
}

extension PhotosContentView: UIContentView {
    var configuration: UIContentConfiguration {
        get {
            ownConfiguration
        }
        set {
            let newConfiguration: PhotosContentConfiguration = newValue as! PhotosContentConfiguration
            
            guard ownConfiguration != newConfiguration else {
                return
            }
            
            ownConfiguration = newConfiguration
        }
    }
    
    func supports(_ configuration: UIContentConfiguration) -> Bool {
        configuration is PhotosContentConfiguration
    }
}
