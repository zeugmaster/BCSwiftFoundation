//
//  File.swift
//  
//
//  Created by Wolf McNally on 12/1/21.
//

import Foundation
@_exported import URKit

public struct KeyRequestBody {
    public let keyType: KeyType
    public let path: DerivationPath
    public let useInfo: UseInfo
    public let isDerivable: Bool
    
    public var cbor: CBOR {
        var a: [OrderedMapEntry] = []
        a.append(.init(key: 1, value: CBOR.boolean(keyType.isPrivate)))
        a.append(.init(key: 2, value: path.taggedCBOR))
        
        if !useInfo.isDefault {
            a.append(.init(key: 3, value: useInfo.taggedCBOR))
        }
        
        if !isDerivable {
            a.append(.init(key: 4, value: CBOR.boolean(isDerivable)))
        }
        
        return CBOR.orderedMap(a)
    }
    
    public var taggedCBOR: CBOR {
        return CBOR.tagged(.keyRequestBody, cbor)
    }

    public init(keyType: KeyType, path: DerivationPath, useInfo: UseInfo, isDerivable: Bool = true) {
        self.keyType = keyType
        self.path = path
        self.useInfo = useInfo
        self.isDerivable = isDerivable
    }

    public init(cbor: CBOR) throws {
        guard case let CBOR.map(pairs) = cbor else {
            throw Error.invalidFormat
        }
        guard let boolItem = pairs[1], case let CBOR.boolean(isPrivate) = boolItem else {
            // Key request doesn't contain isPrivate.
            throw Error.invalidFormat
        }
        guard let pathItem = pairs[2] else {
            // Key request doesn't contain derivation.
            throw Error.invalidFormat
        }
        let path = try DerivationPath(taggedCBOR: pathItem)
        
        let useInfo: UseInfo
        if let pathItem = pairs[3] {
            useInfo = try UseInfo(taggedCBOR: pathItem)
        } else {
            useInfo = UseInfo()
        }
        
        let isDerivable: Bool
        if let isDerivableItem = pairs[4] {
            guard case let CBOR.boolean(d) = isDerivableItem else {
                // Invalid isDerivable field
                throw Error.invalidFormat
            }
            isDerivable = d
        } else {
            isDerivable = true
        }
        
        self.init(keyType: KeyType(isPrivate: isPrivate), path: path, useInfo: useInfo, isDerivable: isDerivable)
    }

    public init?(taggedCBOR: CBOR) throws {
        guard case let CBOR.tagged(.keyRequestBody, cbor) = taggedCBOR else {
            return nil
        }
        try self.init(cbor: cbor)
    }
    
    public enum Error: Swift.Error {
        case invalidFormat
    }
}
