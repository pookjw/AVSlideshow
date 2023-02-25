//
//  PhotosSectionModel.swift
//  AVSlideshow_iOS
//
//  Created by Jinwoo Kim on 2/25/23.
//

actor PhotosSectionModel: Hashable {
    enum SectionType: Sendable {
        case images
    }
    
    static func == (lhs: PhotosSectionModel, rhs: PhotosSectionModel) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
    
    let sectionType: SectionType
    
    init(sectionType: SectionType) {
        self.sectionType = sectionType
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(sectionType)
    }
}
