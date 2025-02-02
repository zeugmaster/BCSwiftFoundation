import Foundation

public struct OutputDescriptorResponseBody: Equatable, TransactionResponseBody {
    public static var type = Envelope("descriptorResponse")
    
    public let descriptor: OutputDescriptor
    public let challengeSignature: Data
    
    public init(descriptor: OutputDescriptor, challengeSignature: Data) {
        self.descriptor = descriptor
        self.challengeSignature = challengeSignature
    }
}

extension OutputDescriptorResponseBody: EnvelopeCodable {
    public var envelope: Envelope {
        descriptor
            .envelope
            .wrap()
            .addType(Self.type)
            .addAssertion("challengeSignature", challengeSignature)
    }

    public init(envelope: Envelope) throws {
        try envelope.checkType(Self.type)
        let descriptor = try OutputDescriptor(envelope: envelope.unwrap())
        let challengeSignature = try envelope.extractObject(Data.self, forPredicate: "challengeSignature")
        self.init(descriptor: descriptor, challengeSignature: challengeSignature)
    }
}
