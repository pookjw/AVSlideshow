//
//  MaxTaskGroup.swift
//  AVSlideshow_iOS
//
//  Created by Jinwoo Kim on 2/26/23.
//

import Foundation

actor MaxTaskGroup<Success: Sendable> {
    private let maxTaskCount: Int
    private let totalCount: Int
    private let operation: @Sendable (Int) async throws -> Success
    
    init(
        maxTaskCount: Int,
        totalCount: Int,
        operation: @Sendable @escaping (Int) async throws -> Success
    ) {
        self.maxTaskCount = maxTaskCount
        self.totalCount = totalCount
        self.operation = operation
    }
    
    var valueStream: AsyncThrowingStream<Success, Error> {
        AsyncThrowingStream<Success, Error> { [maxTaskCount, totalCount, operation] continuation in
            Task {
                await withThrowingTaskGroup(of: Success.self) { group in
                    for index in .zero..<maxTaskCount {
                        group.addTask {
                            try await operation(index)
                        }
                    }
                    
                    var index: Int = maxTaskCount
                    
                    do {
                        for try await value in group {
                            continuation.yield(with: .success(value))
                            
                            if index < totalCount {
                                group.addTask { [index] in
                                    try await operation(index)
                                }
                                
                                index += 1
                            }
                        }
                        
                        continuation.finish(throwing: nil)
                    } catch {
                        group.cancelAll()
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
}
