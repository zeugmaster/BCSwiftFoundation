//
//  Seed.swift
//  BCFoundation
//
//  Created by Wolf McNally on 9/15/21.
//

import Foundation
import WolfBase
import URKit
import SecureComponents

public protocol SeedProtocol: IdentityDigestable, Equatable, PrivateKeysDataProvider, URCodable, EnvelopeCodable {
    var data: Data { get }
    var name: String { get set }
    var note: String { get set }
    var creationDate: Date? { get set }
    
    init?(data: DataProvider, name: String, note: String, creationDate: Date?)
    init?(data: DataProvider)
    /// Copy constructor
    init(_ seed: any SeedProtocol)
    init()
}

public extension SeedProtocol/*: PrivateKeysDataProvider*/ {
    var privateKeysData: Data {
        data
    }
}

public let minSeedSize = 16

public struct Seed: SeedProtocol {
    public static var cborTag: Tag = .seed
    
    public let data: Data
    public var name: String
    public var note: String
    public var creationDate: Date?
    
    public init?(data: DataProvider, name: String = "", note: String = "", creationDate: Date? = nil) {
        let data = data.providedData
        guard data.count >= minSeedSize else {
            return nil
        }
        self.data = data
        self.name = name
        self.note = note
        self.creationDate = creationDate
    }
    
    public init?(data: DataProvider) {
        self.init(data: data, name: "", note: "", creationDate: nil)
    }

    /// Copy constructor
    public init(_ seed: any SeedProtocol) {
        self.init(data: seed.data, name: seed.name, note: seed.note, creationDate: seed.creationDate)!
    }

    public init() {
        self.init(data: SecureRandomNumberGenerator.shared.data(count: minSeedSize))!
    }
}

extension Seed: TransactionResponseBody {
    public static var type = Envelope(.Seed)
}

public extension SeedProtocol {
    init?(hex: String) {
        guard let data = hex.hexData else {
            return nil
        }
        self.init(data: data)
    }

    var hex: String {
        data.hex
    }

    init(count: Int) {
        self.init(data: SecureRandomNumberGenerator.shared.data(count: count))!
    }
}

extension SeedProtocol {
    public var bip39: BIP39 {
        BIP39(data: data)!
    }
    
    public init(bip39: BIP39) {
        self.init(data: bip39.data)!
    }
    
    public init?(mnemonic: String) {
        guard let bip39 = BIP39(mnemonic: mnemonic) else {
            return nil
        }
        self.init(bip39: bip39)
    }
}

public extension SeedProtocol {
    var untaggedCBOR: CBOR {
        var a: Map = [1: data]

        if let creationDate = creationDate {
            a[2] = creationDate.cbor
        }

        if !name.isEmpty {
            a[3] = name.cbor
        }

        if !note.isEmpty {
            a[4] = note.cbor
        }

        return CBOR.map(a)
    }
}

extension SeedProtocol {
    public init(untaggedCBOR: CBOR) throws {
        guard case CBOR.map(let map) = untaggedCBOR else {
            // CBOR doesn't contain a map.
            throw CBORError.invalidFormat
        }
        
        guard
            let dataItem = map[1],
            case let CBOR.bytes(bytes) = dataItem,
            !bytes.isEmpty
        else {
            // CBOR doesn't contain data field.
            throw CBORError.invalidFormat
        }
        let data = bytes.data
        
        let creationDate: Date?
        if let dateItem = map[2] {
            
            creationDate = try Date(cbor: dateItem)
        } else {
            creationDate = nil
        }

        let name: String
        if let nameItem = map[3] {
            guard case let CBOR.text(s) = nameItem else {
                // Name field doesn't contain string.
                throw CBORError.invalidFormat
            }
            name = s
        } else {
            name = ""
        }

        let note: String
        if let noteItem = map[4] {
            guard case let CBOR.text(s) = noteItem else {
                // Note field doesn't contain string.
                throw CBORError.invalidFormat
            }
            note = s
        } else {
            note = ""
        }
        self.init(data: data, name: name, note: note, creationDate: creationDate)!
    }
}

extension SeedProtocol {
    public var identityDigestSource: Data {
        data
    }
}

public extension SeedProtocol {
    var envelope: Envelope {
        sizeLimitedEnvelope(nameLimit: .max, noteLimit: .max).0
    }
    
    init(_ envelope: Envelope) throws {
        try envelope.checkType(.Seed)
        if
            let subjectLeaf = envelope.leaf,
            case CBOR.tagged(.seed, let item) = subjectLeaf
        {
            self = try Self.init(untaggedCBOR: item)
            return
        }

        let data = try envelope.extractSubject(Data.self)
        let name = try envelope.extractOptionalObject(String.self, forPredicate: .hasName) ?? ""
        let note = try envelope.extractOptionalObject(String.self, forPredicate: .note) ?? ""
        let creationDate = try? envelope.extractObject(Date.self, forPredicate: .date)
        guard let result = Self.init(data: data, name: name, note: note, creationDate: creationDate) else {
            throw EnvelopeError.invalidFormat
        }
        self = result
    }
}

public extension SeedProtocol {
    func sizeLimitedEnvelope(nameLimit: Int = 100, noteLimit: Int = 500) -> (Envelope, Bool) {
        var e = Envelope(data)
            .addType(.Seed)
            .addAssertion(.date, creationDate)
        
        var didLimit = false
        
        if !name.isEmpty {
            let limitedName = name.prefix(count: nameLimit)
            didLimit = didLimit || limitedName.count < name.count
            e = e.addAssertion(.hasName, limitedName)
        }
        
        if !note.isEmpty {
            let limitedNote = note.prefix(count: noteLimit)
            didLimit = didLimit || limitedNote.count < note.count
            e = e.addAssertion(.note, limitedNote)
        }
        
        return (e, didLimit)
    }
}
