//
//  OutputDescriptor.swift
//  BCFoundation
//
//  Created by Wolf McNally on 9/2/21.
//

import Foundation
import URKit
import WolfBase
import Flexer

public struct OutputDescriptor {
    public let source: String
    private let astRoot: DescriptorAST
    public var name: String = ""
    public var note: String = ""
    
    public init(_ source: String, name: String = "", note: String = "") throws {
        let source = try Self.validateChecksum(source)
        self.source = source
        let tokens = try DescriptorLexer(source: source).lex()
        self.astRoot = try DescriptorParser(tokens: tokens, source: source).parse()
        self.name = name
        self.note = note
    }
    
    public func scriptPubKey(chain: Chain? = nil, addressIndex: UInt32? = nil, privateKeyProvider: PrivateKeyProvider? = nil, comboOutput: ComboOutput? = nil) -> ScriptPubKey? {
        astRoot.scriptPubKey(chain: chain, addressIndex: addressIndex, privateKeyProvider: privateKeyProvider, comboOutput: comboOutput)
    }
    
    public func hdKey(keyType: KeyType = .public, chain: Chain? = nil, addressIndex: UInt32? = nil, privateKeyProvider: PrivateKeyProvider? = nil, comboOutput: ComboOutput? = nil) -> HDKey? {
        astRoot.hdKey(keyType: keyType, chain: chain, addressIndex: addressIndex, privateKeyProvider: privateKeyProvider, comboOutput: comboOutput)
    }
    
    public var baseKey: HDKey? {
        astRoot.baseKey
    }
    
    public var isCombo: Bool {
        return (astRoot as? DescriptorCombo) != nil
    }

    public enum ComboOutput {
        case pk
        case pkh
        case wpkh
        case sh_wpkh
    }
    
    public var requiresAddressIndex: Bool {
        astRoot.requiresAddressIndex
    }
    
    public var requiresChain: Bool {
        astRoot.requiresChain
    }

    public var unparsed: String {
        astRoot.unparsed
    }
}

extension OutputDescriptor: URCodable {
    public static var cborTag: Tag = .output
    
    public var untaggedCBOR: CBOR {
        astRoot.taggedCBOR
    }
    
    public init(untaggedCBOR: CBOR) throws {
        unimplemented()
    }
}

extension OutputDescriptor: Equatable {
    public static func ==(lhs: OutputDescriptor, rhs: OutputDescriptor) -> Bool {
        lhs.source == rhs.source
    }
}

extension OutputDescriptor: CustomStringConvertible {
    public var description: String {
        source
    }
}

public extension OutputDescriptor {
    var checksum: String {
        Self.checksum(source)!
    }
    
    var sourceWithChecksum: String {
        return "\(source)#\(checksum)"
    }
    
    static func checksum(_ source: String) -> String? {
        descriptorChecksum(source)
    }
    
    static func extractChecksum(_ source: String) -> (String, String?, StringRange?) {
        let regex = try! ~/".*#(.*)$"
        let matches = regex ~?? source
        if matches.isEmpty {
            return (source, nil, nil)
        }
        let range = matches[0].stringRange(in: source, at: 1)
        let checksum = String(source[range])
        let strippedSource = String(source.dropLast(checksum.count + 1))
        return (strippedSource, checksum, range)
    }
    
    static func validateChecksum(_ source: String) throws -> String {
        let (strippedSource, checksum, range) = extractChecksum(source)
        if
            let checksum = checksum,
            let range = range
        {
            guard checksum == Self.checksum(strippedSource) else {
                let token = DescriptorToken(kind: .checksum, range: range)
                throw OutputDescriptorError("Invalid checksum.", token, source: source)
            }
        }
        return strippedSource
    }
}

public extension OutputDescriptor {
    func address(useInfo: UseInfo, chain: Chain?, addressIndex: UInt32?, privateKeyProvider: PrivateKeyProvider? = nil, comboOutput: ComboOutput? = nil) -> Bitcoin.Address? {
        guard let scriptPubKey = self.scriptPubKey(chain: chain, addressIndex: addressIndex, privateKeyProvider: privateKeyProvider, comboOutput: comboOutput) else {
            return nil
        }
        return Bitcoin.Address(scriptPubKey: scriptPubKey, useInfo: useInfo)
    }
    
    func addresses(useInfo: UseInfo, chain: Chain?, indexes: IndexSet, privateKeyProvider: PrivateKeyProvider? = nil, comboOutput: ComboOutput? = nil) -> [UInt32: Bitcoin.Address] {
        var result: [UInt32: Bitcoin.Address] = [:]
        for index in indexes.lazy.map({ UInt32($0) }) {
            result[index] = address(useInfo: useInfo, chain: chain, addressIndex: index, privateKeyProvider: privateKeyProvider, comboOutput: comboOutput)
        }
        return result
    }
    
    func addresses(useInfo: UseInfo, chain: Chain, indexes: Range<UInt32>, privateKeyProvider: PrivateKeyProvider? = nil, comboOutput: ComboOutput? = nil) -> [UInt32: Bitcoin.Address] {
        let indexes = IndexSet(Int(indexes.startIndex)..<Int(indexes.endIndex))
        return addresses(useInfo: useInfo, chain: chain, indexes: indexes, privateKeyProvider: privateKeyProvider, comboOutput: comboOutput)
    }
}

public extension OutputDescriptor {
    func isDerivedFromSeed(_ seed: any SeedProtocol) -> Bool {
        guard
            let descriptorBaseKey = baseKey,
            let seedMasterKey = try? HDKey(seed: seed),
            descriptorBaseKey.parent.originFingerprint == seedMasterKey.keyFingerprint,
            let derivedKey = try? HDKey(parent: seedMasterKey, derivedKeyType: .public, childDerivationPath: descriptorBaseKey.parent),
            descriptorBaseKey.keyData == derivedKey.keyData
        else {
            return false
        }
        return true
    }
}

extension OutputDescriptor: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sourceWithChecksum)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let source = try container.decode(String.self)
        try self.init(source)
    }
}

extension OutputDescriptor: EnvelopeCodable {
    public var envelope: Envelope {
        var e = Envelope(sourceWithChecksum)
            .addType(.OutputDescriptor)
        
        if !name.isEmpty {
            e = e.addAssertion(.hasName, name)
        }
        
        if !note.isEmpty {
            e = e.addAssertion(.note, note)
        }
        
        return e
    }
    
    public init(envelope: Envelope) throws {
        try envelope.checkType(.OutputDescriptor)
        let source = try envelope.extractSubject(String.self)
        let name = try envelope.extractOptionalNonemptyString(forPredicate: .hasName) ?? ""
        let note = try envelope.extractOptionalNonemptyString(forPredicate: .note) ?? ""
        try self.init(source, name: name, note: note)
        guard self.envelope.isEquivalent(to: envelope) else {
            throw EnvelopeError.invalidFormat
        }
    }
}
