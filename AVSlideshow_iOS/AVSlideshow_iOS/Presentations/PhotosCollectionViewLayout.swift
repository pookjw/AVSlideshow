//
//  PhotosCollectionViewLayout.swift
//  AVSlideshow_iOS
//
//  Created by Jinwoo Kim on 2/25/23.
//

import UIKit

@MainActor final class PhotosCollectionViewLayout: UICollectionViewCompositionalLayout {
    convenience init() {
        let configuration: UICollectionViewCompositionalLayoutConfiguration = .init()
        configuration.scrollDirection = .vertical
        
        self.init(
            sectionProvider: { sectionIndex, environment in
                let itemSize: NSCollectionLayoutSize = .init(
                    widthDimension: .fractionalWidth(1.0 / 3.0),
                    heightDimension: .fractionalHeight(1.0)
                )
                let item: NSCollectionLayoutItem = .init(layoutSize: itemSize)
                
                let groupSize: NSCollectionLayoutSize = .init(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .fractionalWidth(1.0 / 3.0)
                )
                
                let group: NSCollectionLayoutGroup = .horizontal(layoutSize: groupSize, repeatingSubitem: item, count: 3)
                let section: NSCollectionLayoutSection = .init(group: group)
                
                return section
            }, 
            configuration: configuration
        )
    }
}
