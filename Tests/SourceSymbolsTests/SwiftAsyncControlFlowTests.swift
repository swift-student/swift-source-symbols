import SourceSymbols
import Testing

@Test(arguments: ["try", "try?", "try!"])
func asyncControlFlowPreservesDeclarationScopes(operatorPrefix: String) throws {
    let statements = [
        "if let packet = \(operatorPrefix) await nextPacket() { let local = packet }",
        "guard let packet = \(operatorPrefix) await nextPacket() else { return }; let local = packet",
        "while let packet = \(operatorPrefix) await nextPacket() { let local = packet; break }",
        "switch \(operatorPrefix) await nextPacket() { case .some: let local = 1; default: break }",
    ]
    for statement in statements {
        let snapshot = SourceSnapshot(text: """
        struct Session {
            func run() async throws {
                \(statement)
            }
            func finish() {}
        }
        """, language: .swift)
        let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
        try expectSnapshotContract(result, from: snapshot)
        #expect(result.diagnostics.isEmpty)
        for name in ["Session", "Session.run()", "Session.run().local", "Session.finish()"] {
            #expect(candidates(.init(name: .qualified(name)), in: result).count == 1)
        }
        let method = try #require(candidates(.init(name: .qualified("Session.run()")), in: result).first)
        #expect(method.kind == .method)
        let header = try #require(method.headerRange)
        #expect(snapshot.text(in: header) == "func run() async throws")
        let body = try #require(snapshot.text(in: method.declarationRange))
        #expect(body.contains(statement))
        #expect(!body.contains("func finish"))
    }
}

@Test func asyncPacketLoopRetainsActorAndFollowingMethods() throws {
    let snapshot = SourceSnapshot(text: """
    actor Client {
        func streamEvents() async throws {
            while let packet = try await connection.nextPacket() {
                switch packet.type {
                case .ping:
                    try await connection.sendPacket(packet)
                case .pong:
                    continue
                case .bye:
                    return
                default:
                    throw Failure.unexpected
                }
            }
        }
        func subscribe() async throws {
            switch try await connection.handleControlPacket(packet) {
            case .ponged: return
            case .bye: return
            case .other: break
            }
            let events = await bus.streamEvents()
        }
        func close() {}
    }
    """, language: .swift)
    let result = try TreeSitterSwiftExtractor().extract(from: snapshot)
    try expectSnapshotContract(result, from: snapshot)
    #expect(result.diagnostics.isEmpty)
    for name in [
        "Client",
        "Client.streamEvents()",
        "Client.subscribe()",
        "Client.subscribe().events",
        "Client.close()",
    ] {
        #expect(candidates(.init(name: .qualified(name)), in: result).count == 1)
    }
    let subscribe = try #require(candidates(.init(name: .qualified("Client.subscribe()")), in: result).first)
    #expect(subscribe.enclosingScopes == ["Client"])
    #expect(snapshot.text(in: subscribe.declarationRange)?
        .hasSuffix("let events = await bus.streamEvents()\n    }") == true)
}
