//
//  SlideshowService.swift
//  AVSlideshow_iOS
//
//  Created by Jinwoo Kim on 2/26/23.
//

import UIKit
import AVFoundation

actor SlideshowService {
    func exportVideo(from images: [UIImage]) async throws -> Data {
        let duration: CMTime = .init(
            seconds: 3.0,
            preferredTimescale: 600
        )
        
        let timeRange: CMTimeRange = .init(
            start: .zero,
            duration: duration
        )
        
        let videoSize: CGSize = .init(width: 1_280, height: 720)
        
        let composition: AVMutableComposition = .init()
        let rootLayer: CALayer = .init()
        rootLayer.frame = .init(origin: .zero, size: videoSize)
        
        let videoComposition: AVMutableVideoComposition = .init()
        videoComposition.renderSize = videoSize
        
        return .init()
    }
}
