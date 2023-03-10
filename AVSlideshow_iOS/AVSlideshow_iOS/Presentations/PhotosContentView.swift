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
    private var selectionImageView: UIImageView!
    
    private var loadingImageTask: Task<Void, Never>?
    private var currentRequestID: PHImageRequestID?
    
    private var boundsChangesTask: Task<Void?, Never>?
    
    private var ownConfiguration: PhotosContentConfiguration!
    
    init(ownConfiguration: PhotosContentConfiguration!) {
        super.init(frame: .null)
        self.ownConfiguration = ownConfiguration
        setupImageView()
        setupProgressView()
        setupSelectionImageView()
        bind()
        updateImage()
        updateSelectionImage()
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
        imageView.clipsToBounds = true
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        addSubview(imageView)
        
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
    
    private func setupSelectionImageView() {
        let selectionImageView: UIImageView = .init(frame: bounds)
        selectionImageView.tintColor = .white
        selectionImageView.backgroundColor = .systemPurple.withAlphaComponent(0.5)
        selectionImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        addSubview(selectionImageView)
        self.selectionImageView = selectionImageView
    }
    
    private func bind() {
        let stream: AsyncPublisher<AnyPublisher<CGRect, Never>> = publisher(for: \.frame, options: [.new])
            .removeDuplicates()
            .debounce(for: 0.1, scheduler: DispatchQueue.global())
            .eraseToAnyPublisher()
            .values
        
        boundsChangesTask = .detached { [weak self] in
            for await _ in stream {
                await self?.updateImage()
            }
        }
    }
    
    private func updateImage() {
        if let currentRequestID: PHImageRequestID {
            PHImageManager.default().cancelImageRequest(currentRequestID)
        }
        loadingImageTask?.cancel()
        
        progressView.isHidden = false
        progressView.setProgress(.zero, animated: false)
        imageView.isHidden = true
        imageView.image = nil
        
        loadingImageTask = .detached { [weak self] in
            let options: PHImageRequestOptions = .init()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            
            /*
             [weak self]??? capture??? ??? ?????? block??? ?????? ????????? self??? ????????? ?????? ?????? ????????? ???????????? ??? ???????????? ??????????????????.
             ????????? progressView??? retain?????? capture??????.
             */
            options.progressHandler = { [progressView = await self?.progressView] progress, error, stopPointer, info in
                Task { @MainActor in
                    progressView?.setProgress(Float(progress), animated: false)
                }
            }
            
            guard
                let asset: PHAsset = await self?.ownConfiguration.asset,
                let size: CGSize = await self?.imageView.bounds.size,
                size != .zero
            else {
                return
            }
            
            let result: (image: UIImage?, info: [AnyHashable : Any]?) = await withCheckedContinuation { continuation in
                Task { @MainActor [weak self] in
                    /*
                     `-[PHImageManager cancelImageRequest:]`??? Main Actor?????? ???????????? ?????? `currentRequestID` ?????? Main Actor?????? ???????????? ????????? Race Condition??? ????????? ?????? Main Actor?????? ????????????.
                     Actor??? ????????? ???????????? Main Actor?????? ???????????? ????????? ??? ?????????.
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
            
            if 
                let isCancelled: Bool = result.info?[PHImageCancelledKey] as? Bool,
                isCancelled
            {
                print("Cancelled by PHImageManager.")
                return
            } else if let error: NSError = result.info?[PHImageErrorKey] as? NSError {
                print(error)
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
                self.currentRequestID = nil
                UIView.animate(withDuration: 0.1) { 
                    self.imageView.alpha = 1.0
                }
            }
        }
    }
    
    private func updateSelectionImage() {
        if ownConfiguration.isSelected {
            selectionImageView.image = .init(systemName: "checkmark")
            selectionImageView.isHidden = false
        } else {
            selectionImageView.image = nil
            selectionImageView.isHidden = true
        }
    }
}

extension PhotosContentView: UIContentView {
    var configuration: UIContentConfiguration {
        get {
            ownConfiguration
        }
        set {
            let oldConfiguration: PhotosContentConfiguration = ownConfiguration
            let newConfiguration: PhotosContentConfiguration = newValue as! PhotosContentConfiguration
            
            ownConfiguration = newConfiguration
            
            if oldConfiguration.asset != newConfiguration.asset {
                updateImage()
            }
            
            if oldConfiguration.isSelected != newConfiguration.isSelected {
                updateSelectionImage()
            }
        }
    }
    
    func supports(_ configuration: UIContentConfiguration) -> Bool {
        configuration is PhotosContentConfiguration
    }
}
