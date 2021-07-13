//
//  RealtimeClient.swift
//  ably
//
//  Created by Ricardo Pereira on 26/09/2015.
//  Copyright (c) 2015 Ably. All rights reserved.
//

import Ably
import Quick
import Nimble

class RealtimeClient: QuickSpec {

    func checkError(_ errorInfo: ARTErrorInfo?, withAlternative message: String) {
        if let error = errorInfo {
            XCTFail("\((error ).code): \(error.message)")
        }
        else if !message.isEmpty {
            XCTFail(message)
        }
    }

    func checkError(_ errorInfo: ARTErrorInfo?) {
        checkError(errorInfo, withAlternative: "")
    }

    override func spec() {
        describe("RealtimeClient") {
            // G4
            it("All WebSocket connections should include the current API version") {
                let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
                defer { client.dispose(); client.close() }
                let channel = client.channels.get("test")
                waitUntil(timeout: testTimeout) { done in
                    channel.publish(nil, data: "message") { error in
                        expect(error).to(beNil())
                        let transport = client.internal.transport as! TestProxyTransport
                                                
                        // This test should not directly validate version against ARTDefault.version(), as
                        // ultimately the version header has been derived from that value.
                        expect(transport.lastUrl!.query).to(haveParam("v", withValue: "1.2"))
                        
                        done()
                    }
                }
            }

            // RTC1
            context("options") {
                it("should support the same options as the Rest client") {
                    let options = AblyTests.commonAppSetup() //Same as Rest
                    options.clientId = "client_string"

                    let client = ARTRealtime(options: options)
                    defer { client.close() }

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.on { stateChange in
                            let stateChange = stateChange!
                            let state = stateChange.current
                            let errorInfo = stateChange.reason
                            switch state {
                            case .connecting, .closing, .closed:
                                break
                            case .failed:
                                self.checkError(errorInfo, withAlternative: "Failed state")
                                done()
                            default:
                                expect(state).to(equal(ARTRealtimeConnectionState.connected))
                                done()
                                break
                            }
                        }
                    }
                }
                
                //RTC1a
                it("should echoMessages option be true by default") {
                    let options = ARTClientOptions()
                    expect(options.echoMessages) == true
                }
                
                //RTC1b
                it("should autoConnect option be true by default") {
                    let options = ARTClientOptions()
                    expect(options.autoConnect) == true
                }

                //RTC1c
                it("should attempt to recover the connection state if recover string is assigned") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "client_string"

                    // First connection
                    let client = ARTRealtime(options: options)
                    defer { client.close() }

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.on { stateChange in
                            let stateChange = stateChange!
                            let state = stateChange.current
                            let errorInfo = stateChange.reason
                            switch state {
                            case .failed:
                                self.checkError(errorInfo, withAlternative: "Failed state")
                                done()
                            case .connected:
                                self.checkError(errorInfo)
                                expect(client.connection.recoveryKey).to(equal("\(client.connection.key ?? ""):\(client.connection.serial):\(client.internal.msgSerial)"), description: "recoveryKey wrong formed")
                                options.recover = client.connection.recoveryKey
                                done()
                            default:
                                break
                            }
                        }
                    }
                    client.connection.off()

                    // New connection
                    let newClient = ARTRealtime(options: options)
                    defer { newClient.close() }

                    waitUntil(timeout: testTimeout) { done in
                        newClient.connection.on { stateChange in
                            let stateChange = stateChange!
                            let state = stateChange.current
                            let errorInfo = stateChange.reason
                            switch state {
                            case .failed:
                                self.checkError(errorInfo, withAlternative: "Failed state")
                                done()
                            case .connected:
                                self.checkError(errorInfo)
                                done()
                            default:
                                break
                            }
                        }
                    }
                    newClient.connection.off()
                }

                //RTC1d
                it("should modify the realtime endpoint host if realtimeHost is assigned") {
                    let options = ARTClientOptions(key: "secret:key")
                    options.realtimeHost = "fake.ably.io"
                    options.autoConnect = false
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }

                    waitUntil(timeout: testTimeout.multiplied(by: 2)) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        client.connection.once(.connecting) { _ in
                            guard let webSocketTransport = client.internal.transport as? ARTWebSocketTransport else {
                                fail("Transport should be of type ARTWebSocketTransport"); done()
                                return
                            }
                            expect(webSocketTransport.websocketURL).toNot(beNil())
                            expect(webSocketTransport.websocketURL?.host).to(equal("fake.ably.io"))
                            partialDone()
                        }
                        client.connection.once(.disconnected) { stateChange in
                            partialDone()
                        }
                        client.connect()
                    }
                }
                
                //RTC1e
                it("should modify both the REST and realtime endpoint if environment string is assigned") {
                    let options = AblyTests.commonAppSetup()
                    
                    let oldRestHost = options.restHost
                    let oldRealtimeHost = options.realtimeHost

                    // Change REST and realtime endpoint hosts
                    options.environment = "test"
                    
                    expect(options.restHost).to(equal("test-rest.ably.io"))
                    expect(options.realtimeHost).to(equal("test-realtime.ably.io"))
                    // Extra care
                    expect(oldRestHost).to(equal("\(getEnvironment())-rest.ably.io"))
                    expect(oldRealtimeHost).to(equal("\(getEnvironment())-realtime.ably.io"))
                }
            }

            // RTC2
            it("should have access to the underlying Connection object") {
                let options = AblyTests.commonAppSetup()
                options.autoConnect = false
                let client = ARTRealtime(options: options)
                expect(client.connection).to(beAKindOf(ARTConnection.self))
            }

            // RTC3
            it("should provide access to the underlying Channels object") {
                let options = AblyTests.commonAppSetup()
                options.autoConnect = false

                let client = ARTRealtime(options: options)
                defer { client.dispose(); client.close() }

                client.channels.get("test").subscribe({ message in
                    // Attached
                })

                expect(client.channels.get("test")).toNot(beNil())
            }

            context("Auth object") {

                // RTC4
                it("should provide access to the Auth object") {
                    let options = AblyTests.commonAppSetup()
                    let client = ARTRealtime(options: options)
                    defer { client.close() }
                    expect(client.auth.internal.options.key).to(equal(options.key))
                }

                // RTC4a
                it("clientId may be populated when the connection is established") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "client_string"
                    let client = ARTRealtime(options: options)
                    defer { client.close() }

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.on { stateChange in
                            let stateChange = stateChange!
                            let state = stateChange.current
                            let errorInfo = stateChange.reason
                            switch state {
                            case .failed:
                                self.checkError(errorInfo, withAlternative: "Failed state")
                                done()
                            case .connected:
                                self.checkError(errorInfo)
                                expect(client.auth.clientId).to(equal(options.clientId))
                                done()
                            default:
                                break
                            }
                        }
                    }
                }
            }

            context("stats") {
                let query = ARTStatsQuery()
                query.unit = .minute

                // RTC5a
                it("should present an async interface") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    // Async
                    waitUntil(timeout: testTimeout) { done in
                        // Proxy from `client.internal.rest.stats`
                        expect {
                            try client.stats(query, callback: { paginated, error in
                                expect(paginated).toNot(beNil())
                                done()
                            })
                        }.toNot(throwError() { err in fail("\(err)"); done() })
                    }
                }

                // RTC5b
                xit("should accept all the same params as RestClient") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    var paginatedResult: ARTPaginatedResult<AnyObject>?
                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { _ in
                            done()
                        }
                    }

                    // Realtime
                    expect {
                        try client.stats(query, callback: { paginated, error in
                            if let e = error {
                                XCTFail(e.localizedDescription)
                            }
                            paginatedResult = paginated as! ARTPaginatedResult<AnyObject>?
                        })
                    }.toNot(throwError())
                    expect(paginatedResult).toEventuallyNot(beNil(), timeout: testTimeout)
                    if paginatedResult == nil {
                        return
                    }

                    // Rest
                    waitUntil(timeout: testTimeout) { done in
                        expect {
                            try client.internal.rest.stats(query, callback: { paginated, error in
                                defer { done() }
                                if let e = error {
                                    XCTFail(e.localizedDescription)
                                    return
                                }
                                guard let paginated = paginated else {
                                    XCTFail("both paginated and error are nil")
                                    return
                                } 
                                expect(paginated.items.count).to(equal(paginatedResult!.items.count))
                            })
                        }.toNot(throwError() { err in fail("\(err)"); done() })
                    }
                }
            }

            context("time") {
                // RTC6a
                it("should present an async interface") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }
                    // Async
                    waitUntil(timeout: testTimeout) { done in
                        // Proxy from `client.internal.rest.time`
                        client.time({ date, error in
                            expect(date).toNot(beNil())
                            done()
                        })
                    }
                }
            }

            // RTC7
            it("should use the configured timeouts specified") {
                let options = AblyTests.commonAppSetup()
                options.suspendedRetryTimeout = 6.0

                let client = ARTRealtime(options: options)
                defer { client.close() }

                var start: NSDate?
                var endInterval: UInt?

                waitUntil(timeout: testTimeout.incremented(by: options.suspendedRetryTimeout)) { done in
                    client.connection.on { stateChange in
                        let stateChange = stateChange!
                        let state = stateChange.current
                        let errorInfo = stateChange.reason
                        switch state {
                        case .failed:
                            self.checkError(errorInfo, withAlternative: "Failed state")
                            done()
                        case .connecting:
                            if let start = start {
                                endInterval = UInt(start.timeIntervalSinceNow * -1)
                                done()
                            }
                        case .connected:
                            self.checkError(errorInfo)

                            if start == nil {
                                // Force
                                delay(0) {
                                    client.internal.onSuspended()
                                }
                            }
                        case .suspended:
                            start = NSDate()
                        default:
                            break
                        }
                    }
                }

                if let secs = endInterval {
                    expect(secs).to(beLessThanOrEqualTo(UInt(options.suspendedRetryTimeout)))
                }

                expect(client.internal.connectionStateTtl).to(equal(120 as TimeInterval /*seconds*/))
            }

            // RTC8
            context("Auth#authorize should upgrade the connection with current token") {

                // RTC8a
                it("in the CONNECTED state and auth#authorize is called, the client must obtain a new token, send an AUTH ProtocolMessage with an auth attribute") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    options.useTokenAuth = true
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                        client.connect()
                    }

                    guard let firstToken = client.auth.tokenDetails?.token else {
                        fail("Client has no token"); return
                    }

                    guard let transport = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport is not set"); return
                    }

                    waitUntil(timeout: testTimeout) { done in
                        client.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is nil"); done(); return
                            }

                            let authMessages = transport.protocolMessagesSent.filter({ $0.action == .auth })
                            expect(authMessages).to(haveCount(1))

                            guard let authMessage = authMessages.first else {
                                fail("Missing AUTH protocol message"); done(); return
                            }

                            expect(authMessage.auth).toNot(beNil())

                            guard let accessToken = authMessage.auth?.accessToken else {
                                fail("Missing accessToken from AUTH ProtocolMessage auth attribute"); done(); return
                            }

                            expect(accessToken).toNot(equal(firstToken))
                            expect(tokenDetails.token).toNot(equal(firstToken))
                            expect(tokenDetails.token).to(equal(accessToken))

                            expect(client.internal.transport).to(beIdenticalTo(transport))

                            done()
                        }
                    }
                }

                // RTC8a1 - part 1
                it("when the authentication token change is successful, then the client should receive a new CONNECTED ProtocolMessage") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    let testToken = getTestToken()
                    options.token = testToken
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                        client.connect()
                    }

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)

                        client.connection.once(.connected) { stateChange in
                            fail("Should not receive a CONNECTED event because the connection is already connected"); partialDone(); return
                        }

                        client.connection.once(.update) { stateChange in
                            guard let stateChange = stateChange else {
                                fail("ConnectionStateChange is nil"); partialDone(); return
                            }
                            expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connected))
                            expect(stateChange.reason).to(beNil())

                            guard let transport = client.internal.transport as? TestProxyTransport else {
                                fail("TestProxyTransport is not set"); partialDone(); return
                            }
                            let connectedMessages = transport.protocolMessagesReceived.filter{ $0.action == .connected }
                            expect(connectedMessages).to(haveCount(2))

                            guard let connectedAfterAuth = connectedMessages.last, let connectionDetailsAfterAuth = connectedAfterAuth.connectionDetails else {
                                fail("Missing CONNECTED protocol message after AUTH protocol message"); partialDone(); return
                            }

                            expect(client.auth.clientId).to(beNil())
                            expect(connectionDetailsAfterAuth.clientId).to(beNil())
                            expect(client.connection.key).to(equal(connectionDetailsAfterAuth.connectionKey))
                            partialDone()
                        }

                        client.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is nil"); partialDone(); return
                            }
                            expect(tokenDetails.token).toNot(equal(testToken))
                            partialDone()
                        }

                        expect(client.connection.errorReason).to(beNil())
                    }

                    expect(client.auth.tokenDetails?.token).toNot(equal(testToken))
                }

                // RTC8a1 - part 2
                it("performs an upgrade of capabilities without any loss of continuity or connectivity during the upgrade process") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    let testToken = getTestToken(capability: "{\"test\":[\"subscribe\"]}")
                    options.token = testToken
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                        client.connect()
                    }

                    let channel = client.channels.get("foo")
                    waitUntil(timeout: testTimeout) { done in
                        channel.once(.failed) { stateChange in
                            guard let error = stateChange?.reason else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error.message).to(contain("Channel denied access based on given capability"))
                            done()
                        }
                        channel.attach()
                    }

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)

                        client.connection.once(.update) { stateChange in
                            guard let stateChange = stateChange else {
                                fail("ConnectionStateChange is nil"); partialDone(); return
                            }
                            expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connected))
                            expect(stateChange.reason).to(beNil())
                            partialDone()
                        }

                        client.connection.once(.connected) { _ in
                            fail("Already connected")
                        }
                        client.connection.once(.disconnected) { _ in
                            fail("Lost connectivity")
                        }
                        client.connection.once(.suspended) { _ in
                            fail("Lost continuity")
                        }
                        client.connection.once(.failed) { _ in
                            fail("Should not receive any failure")
                        }

                        let tokenParams = ARTTokenParams()
                        tokenParams.capability = "{\"*\":[\"*\"]}"

                        client.auth.authorize(tokenParams, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is nil"); partialDone(); return
                            }
                            expect(tokenDetails.token).toNot(equal(testToken))
                            expect(tokenDetails.capability).to(equal(tokenParams.capability))
                            partialDone()
                        }
                    }

                    expect(client.auth.tokenDetails?.token).toNot(equal(testToken))

                    guard let transport = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport is not set"); return
                    }

                    expect(transport.protocolMessagesReceived.filter{ $0.action == .disconnected }).to(beEmpty())
                    // Should have one error: Channel denied access
                    expect(transport.protocolMessagesReceived.filter{ $0.action == .error }).to(haveCount(1))

                    // Retry Channel attach
                    waitUntil(timeout: testTimeout) { done in
                        channel.once(.failed) { _ in
                            fail("Should not reach Failed state"); done(); return
                        }
                        channel.once(.attached) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                        channel.attach()
                    }

                    expect(client.auth.tokenDetails?.token).toNot(equal(testToken))
                }

                // RTC8a1 - part 3
                it("when capabilities are downgraded, client should receive an ERROR ProtocolMessage with a channel property") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    let testToken = getTestToken()
                    options.token = testToken
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)

                    let channel = client.channels.get("foo")
                    waitUntil(timeout: testTimeout) { done in
                        client.connect()
                        channel.attach() { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)

                        channel.once(.failed) { stateChange in
                            guard let error = stateChange?.reason else {
                                fail("ErrorInfo is nil"); partialDone(); return
                            }
                            expect(error).to(beIdenticalTo(channel.errorReason))
                            expect((error ).code).to(equal(40160))

                            guard let transport = client.internal.transport as? TestProxyTransport else {
                                fail("TestProxyTransport is not set"); partialDone(); return
                            }

                            let errorMessages = transport.protocolMessagesReceived.filter{ $0.action == .error }
                            expect(errorMessages).to(haveCount(1))

                            guard let errorMessage = errorMessages.first else {
                                fail("Missing ERROR protocol message"); partialDone(); return
                            }
                            expect(errorMessage.channel).to(contain("test"))
                            expect(errorMessage.error?.code).to(equal((error ).code))
                            partialDone()
                        }

                        let tokenParams = ARTTokenParams()
                        tokenParams.capability = "{\"test\":[\"subscribe\"]}"

                        client.auth.authorize(tokenParams, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is nil"); partialDone(); return
                            }
                            expect(tokenDetails.token).toNot(equal(testToken))
                            expect(tokenDetails.capability).to(equal(tokenParams.capability))
                            partialDone()
                        }
                    }

                    expect(client.auth.tokenDetails?.token).toNot(equal(testToken))
                }

                // RTC8a2
                it("when the authentication token change fails, client should receive an ERROR ProtocolMessage triggering the connection to transition to the FAILED state") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    options.clientId = "ios"
                    options.useTokenAuth = true
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                        client.connect()
                    }

                    var connectionError: NSError?
                    var authError: NSError?

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)

                        client.connection.once(.failed) { stateChange in
                            guard let stateChange = stateChange else {
                                fail("ConnectionStateChange is nil"); partialDone(); return
                            }
                            expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connected))
                            expect(stateChange.reason).toNot(beNil())
                            connectionError = stateChange.reason
                            partialDone()
                        }

                        let invalidToken = "xxxxxxxxxxxx"
                        let authOptions = ARTAuthOptions()
                        authOptions.authCallback = { tokenParams, completion in
                            completion(invalidToken as ARTTokenDetailsCompatible, nil)
                        }

                        client.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                            guard let error = error else {
                                fail("ErrorInfo is nil"); partialDone(); return
                            }
                            expect(error.localizedDescription).to(contain("Invalid accessToken"))
                            expect(tokenDetails?.token).to(equal(invalidToken))
                            authError = error as NSError?
                            partialDone()
                        }
                    }

                    expect(authError).to(beIdenticalTo(connectionError))
                }

                it("authorize call should complete with an error if the request fails") {
                    let options = AblyTests.clientOptions()
                    let testToken = getTestToken()
                    options.token = testToken
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        let tokenParams = ARTTokenParams()
                        tokenParams.clientId = "john"

                        let simulatedError = NSError(domain: ARTAblyErrorDomain, code: 1234, userInfo: nil)

                        let authOptions = ARTAuthOptions()
                        authOptions.authCallback = { tokenParams, completion in
                            DispatchQueue.main.async {
                                completion(nil, simulatedError)
                            }
                        }

                        client.auth.authorize(tokenParams, options: authOptions) { tokenDetails, error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error as NSError).to(equal(simulatedError))
                            expect(tokenDetails).to(beNil())
                            done()
                        }
                    }

                    expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                    expect(client.auth.tokenDetails?.token).to(equal(testToken))
                }

                // RTC8a3
                it("authorize call should be indicated as completed with the new token or error only once realtime has responded to the AUTH with either a CONNECTED or ERROR respectively") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    options.useTokenAuth = true
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                        client.connect()
                    }

                    waitUntil(timeout: testTimeout) { done in
                        client.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())

                            guard let transport = client.internal.transport as? TestProxyTransport else {
                                fail("TestProxyTransport is not set"); done(); return
                            }

                            expect(transport.protocolMessagesSent.filter({ $0.action == .auth })).to(haveCount(1))
                            expect(transport.protocolMessagesReceived.filter({ $0.action == .connected })).to(haveCount(2))
                            expect(transport.protocolMessagesReceived.filter({ $0.action == .error })).to(haveCount(0))
                            done()
                        }
                    }
                }

                // RTC8b
                it("when connection is CONNECTING, all current connection attempts should be halted, and after obtaining a new token the library should immediately initiate a connection attempt using the new token") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    options.useTokenAuth = true
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)

                    var connections = 0
                    let hook1 = TestProxyTransport.testSuite_injectIntoClassMethod(#selector(TestProxyTransport.connect(withToken:))) {
                        connections += 1
                    }
                    defer { hook1?.remove() }

                    var connectionsConnected = 0
                    let hook2 = client.connection.on(.connected) { _ in
                        connectionsConnected += 1
                    }
                    defer { client.connection.off(hook2) }

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connecting) { stateChange in
                            expect(stateChange?.reason).to(beNil())

                            let authOptions = ARTAuthOptions()
                            authOptions.key = AblyTests.commonAppSetup().key

                            client.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                                expect(error).to(beNil())
                                guard let tokenDetails = tokenDetails else {
                                    fail("TokenDetails is nil"); done(); return
                                }
                                expect(tokenDetails.token).toNot(beNil())
                                expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))

                                guard let transport = client.internal.transport as? TestProxyTransport else {
                                    fail("TestProxyTransport is not set"); done(); return
                                }
                                expect(transport.protocolMessagesReceived.filter({ $0.action == .connected })).to(haveCount(1))
                                done()
                            }
                        }
                        client.connect()
                    }

                    expect(connections) == 2
                    expect(connectionsConnected) == 1

                    expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
                }

                // RTC8b1 - part 1
                it("authorize call should complete with the new token once the connection has moved to the CONNECTED state") {
                    let options = AblyTests.clientOptions()
                    options.autoConnect = false
                    let testToken = getTestToken()
                    options.token = testToken
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }

                    waitUntil(timeout: testTimeout) { done in
                        let authOptions = ARTAuthOptions()
                        authOptions.key = AblyTests.commonAppSetup().key

                        client.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is nil"); done(); return
                            }
                            expect(tokenDetails.token).toNot(equal(testToken))
                            done()
                        }
                    }

                    expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                }

                // RTC8b1 - part 2
                it("authorize call should complete with an error if the connection moves to the FAILED state") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    options.useTokenAuth = true
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                        client.connect()
                    }

                    let hook = client.auth.internal.testSuite_injectIntoMethod(after: #selector(client.auth.internal._authorize(_:options:callback:))) {
                        guard let transport = client.internal.transport as? TestProxyTransport else {
                            fail("TestProxyTransport is not set"); return
                        }
                        transport.simulateIncomingError()
                    }
                    defer { hook.remove() }

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)

                        client.connection.once(.failed) { stateChange in
                            guard let error = stateChange?.reason else {
                                fail("ErrorInfo is nil"); partialDone(); return
                            }
                            expect(error.message).to(contain("Fail test"))
                            partialDone()
                        }

                        client.auth.authorize(nil, options: nil) { tokenDetails, error in
                            guard let error = error else {
                                fail("ErrorInfo is nil"); partialDone(); return
                            }
                            expect((error as NSError).code) == URLError.cancelled.rawValue
                            expect(client.connection.errorReason?.localizedDescription).to(contain("Fail test"))
                            expect(tokenDetails).to(beNil())
                            partialDone()
                        }
                    }

                    expect(client.connection.state).to(equal(ARTRealtimeConnectionState.failed))
                }

                // RTC8b1 - part 3
                it("authorize call should complete with an error if the connection moves to the SUSPENDED state") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    options.useTokenAuth = true
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                        client.connect()
                    }

                    let hook = client.auth.internal.testSuite_injectIntoMethod(after: #selector(client.auth.internal._authorize(_:options:callback:))) {
                        client.internal.onSuspended()
                    }
                    defer { hook.remove() }

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)

                        client.connection.once(.suspended) { _ in
                            partialDone()
                        }

                        client.auth.authorize(nil, options: nil) { tokenDetails, error in
                            guard let error = error else {
                                fail("ErrorInfo is nil"); partialDone(); return
                            }
                            expect((error as NSError).code) == URLError.cancelled.rawValue
                            expect(tokenDetails).to(beNil())
                            partialDone()
                        }
                    }

                    expect(client.connection.state).to(equal(ARTRealtimeConnectionState.suspended))
                }

                // RTC8b1 - part 4
                it("authorize call should complete with an error if the connection moves to the CLOSED state") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    options.useTokenAuth = true
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                        client.connect()
                    }

                    let hook = client.auth.internal.testSuite_injectIntoMethod(after: #selector(client.auth.internal._authorize(_:options:callback:))) {
                        delay(0) {
                            client.close()
                        }
                    }
                    defer { hook.remove() }

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)

                        client.connection.once(.closed) { _ in
                            partialDone()
                        }

                        client.auth.authorize(nil, options: nil) { tokenDetails, error in
                            guard let error = error else {
                                fail("Error is nil"); partialDone(); return
                            }
                            expect((error as NSError).code) == URLError.cancelled.rawValue
                            expect(tokenDetails).to(beNil())
                            partialDone()
                        }
                    }

                    expect(client.connection.state).to(equal(ARTRealtimeConnectionState.closed))
                }

                // RTC8c - part 1
                it("when the connection is in the SUSPENDED state when auth#authorize is called, after obtaining a token the library should move to the CONNECTING state and initiate a connection attempt using the new token") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    let testToken = getTestToken()
                    options.token = testToken
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                        client.connect()
                    }

                    client.internal.onSuspended()
                    expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.suspended), timeout: testTimeout)

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(3, done: done)

                        client.connection.once(.connecting) { stateChange in
                            guard let stateChange = stateChange else {
                                fail("ConnectionStateChange is nil"); partialDone(); return
                            }
                            expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.suspended))
                            expect(stateChange.reason).to(beNil())
                            partialDone()
                        }

                        client.connection.once(.connected) { stateChange in
                            guard let stateChange = stateChange else {
                                fail("ConnectionStateChange is nil"); partialDone(); return
                            }
                            expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connecting))
                            expect(stateChange.reason).to(beNil())
                            partialDone()
                        }

                        client.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is nil"); partialDone(); return
                            }

                            expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                            expect(tokenDetails.token).toNot(equal(testToken))

                            guard let transport = client.internal.transport as? TestProxyTransport else {
                                fail("TestProxyTransport is not set"); partialDone(); return
                            }
                            expect(transport.protocolMessagesSent.filter({ $0.action == .auth })).to(haveCount(0))
                            expect(transport.protocolMessagesReceived.filter({ $0.action == .connected })).to(haveCount(1)) //New transport
                            partialDone()
                        }
                    }
                }

                // RTC8c - part 2
                it("when the connection is in the CLOSED state when auth#authorize is called, after obtaining a token the library should move to the CONNECTING state and initiate a connection attempt using the new token") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    let testToken = getTestToken()
                    options.token = testToken
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                        client.connect()
                    }

                    client.close()
                    expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.closed), timeout: testTimeout)

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(3, done: done)

                        client.connection.once(.connecting) { stateChange in
                            guard let stateChange = stateChange else {
                                fail("ConnectionStateChange is nil"); partialDone(); return
                            }
                            expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.closed))
                            expect(stateChange.reason).to(beNil())
                            partialDone()
                        }

                        client.connection.once(.connected) { stateChange in
                            guard let stateChange = stateChange else {
                                fail("ConnectionStateChange is nil"); partialDone(); return
                            }
                            expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connecting))
                            expect(stateChange.reason).to(beNil())
                            partialDone()
                        }

                        client.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is nil"); partialDone(); return
                            }

                            expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                            expect(tokenDetails.token).toNot(equal(testToken))

                            guard let transport = client.internal.transport as? TestProxyTransport else {
                                fail("TestProxyTransport is not set"); partialDone(); return
                            }
                            expect(transport.protocolMessagesSent.filter({ $0.action == .auth })).to(haveCount(0))
                            expect(transport.protocolMessagesReceived.filter({ $0.action == .connected })).to(haveCount(1)) //New transport
                            partialDone()
                        }
                    }
                }

                // RTC8c - part 3
                it("when the connection is in the DISCONNECTED state when auth#authorize is called, after obtaining a token the library should move to the CONNECTING state and initiate a connection attempt using the new token") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    let testToken = getTestToken()
                    options.token = testToken
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                        client.connect()
                    }

                    client.internal.onDisconnected()
                    expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.disconnected), timeout: testTimeout)

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(3, done: done)

                        client.connection.once(.connecting) { stateChange in
                            guard let stateChange = stateChange else {
                                fail("ConnectionStateChange is nil"); partialDone(); return
                            }
                            expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.disconnected))
                            expect(stateChange.reason).to(beNil())
                            partialDone()
                        }

                        client.connection.once(.connected) { stateChange in
                            guard let stateChange = stateChange else {
                                fail("ConnectionStateChange is nil"); partialDone(); return
                            }
                            expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connecting))
                            expect(stateChange.reason).to(beNil())
                            partialDone()
                        }

                        client.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is nil"); partialDone(); return
                            }

                            expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                            expect(tokenDetails.token).toNot(equal(testToken))

                            guard let transport = client.internal.transport as? TestProxyTransport else {
                                fail("TestProxyTransport is not set"); partialDone(); return
                            }
                            expect(transport.protocolMessagesSent.filter({ $0.action == .auth })).to(haveCount(0))
                            expect(transport.protocolMessagesReceived.filter({ $0.action == .connected })).to(haveCount(1)) //New transport
                            partialDone()
                        }
                    }
                }

                // RTC8c - part 4
                it("when the connection is in the FAILED state when auth#authorize is called, after obtaining a token the library should move to the CONNECTING state and initiate a connection attempt using the new token") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    let testToken = getTestToken()
                    options.token = testToken
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { stateChange in
                            expect(stateChange?.reason).to(beNil())
                            done()
                        }
                        client.connect()
                    }

                    client.internal.onError(AblyTests.newErrorProtocolMessage())
                    expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.failed), timeout: testTimeout)

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(3, done: done)

                        client.connection.once(.connecting) { stateChange in
                            guard let stateChange = stateChange else {
                                fail("ConnectionStateChange is nil"); partialDone(); return
                            }
                            expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.failed))
                            expect(stateChange.reason).to(beNil())
                            partialDone()
                        }

                        client.connection.once(.connected) { stateChange in
                            guard let stateChange = stateChange else {
                                fail("ConnectionStateChange is nil"); partialDone(); return
                            }
                            expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connecting))
                            expect(stateChange.reason).to(beNil())
                            partialDone()
                        }

                        client.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is nil"); partialDone(); return
                            }

                            expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                            expect(tokenDetails.token).toNot(equal(testToken))

                            guard let transport = client.internal.transport as? TestProxyTransport else {
                                fail("TestProxyTransport is not set"); partialDone(); return
                            }
                            expect(transport.protocolMessagesSent.filter({ $0.action == .auth })).to(haveCount(0))
                            expect(transport.protocolMessagesReceived.filter({ $0.action == .connected })).to(haveCount(1)) //New transport
                            partialDone()
                        }
                    }
                }
            }

            // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
            // https://github.com/ably/ably-cocoa/issues/577
            xit("background behaviour") {
                waitUntil(timeout: testTimeout) { done in
                  URLSession.shared.dataTask(with: URL(string:"https://ably.io")!) { _ , _ , _  in
                        let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                        realtime.channels.get("foo").attach { error in
                            expect(error).to(beNil())
                            realtime.close()
                            done()
                        }
                    }.resume()
                }
            }

            it("should accept acks with different order") {
                let realtime = AblyTests.newRealtime(AblyTests.commonAppSetup())
                defer { realtime.dispose(); realtime.close() }
                let channel = realtime.channels.get("foo")
                waitUntil(timeout: testTimeout) { done in
                    channel.attach { error in
                        expect(error).to(beNil())
                        done()
                    }
                }
                guard let transport = realtime.internal.transport as? TestProxyTransport else {
                    fail("TestProxyTransport is not set"); return
                }

                waitUntil(timeout: testTimeout) { done in
                    transport.beforeProcessingReceivedMessage = { pm in
                        if pm.action == .ack, let msgSerial = pm.msgSerial {
                            switch msgSerial.intValue {
                            case 0:
                                pm.msgSerial = 3
                            case 1:
                                pm.msgSerial = 2
                            case 2:
                                pm.msgSerial = 1
                            default:
                                pm.msgSerial = 0
                            }
                        }
                    }

                    let partialDone = AblyTests.splitDone(4, done: done)
                    channel.publish("test1", data: nil) { error in
                        expect(error).to(beNil())
                        partialDone()
                    }
                    channel.publish("test2", data: nil) { error in
                        expect(error).to(beNil())
                        partialDone()
                    }
                    channel.publish("test3", data: nil) { error in
                        expect(error).to(beNil())
                        partialDone()
                    }
                    channel.publish("test4", data: nil) { error in
                        expect(error).to(beNil())
                        partialDone()
                    }
                }
            }

            it("transport should guarantee the incoming message order") {
                let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                defer { realtime.dispose(); realtime.close() }
                waitUntil(timeout: testTimeout) { done in
                    realtime.connection.on(.connected) { _ in
                        done()
                    }
                }
                guard let webSocketTransport = realtime.internal.transport as? ARTWebSocketTransport else {
                    fail("should be using a WebSocket transport"); return
                }

                var result: [Int] = []
                let expectedOrder = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30]

                waitUntil(timeout: testTimeout) { done in
                    let partialDone = AblyTests.splitDone(expectedOrder.count, done: done)

                    realtime.internal.testSuite_getArgument(from: NSSelectorFromString("ack:"), at: 0) { object in
                        guard let value = (object as? ARTProtocolMessage)?.msgSerial?.intValue else {
                            return
                        }
                        result.append(value)
                        partialDone()
                    }

                    for i in expectedOrder {
                        let message = ARTProtocolMessage()
                        message.action = .ack
                        message.msgSerial = i as NSNumber
                        webSocketTransport.webSocket(webSocketTransport.websocket!, didReceiveMessage: message)
                    }
                }

                expect(result).to(equal(expectedOrder))
            }
            
            it("subscriber should receive messages in the same order in which they have been sent") {
                let options = AblyTests.commonAppSetup()
                let realtime1 = ARTRealtime(options: options)
                let realtime2 = ARTRealtime(options: options)
                defer {
                    realtime1.dispose(); realtime1.close();
                    realtime2.dispose(); realtime2.close();
                }
                
                let subscribeChannel = realtime1.channels.get("testing")
                let sendChannel = realtime2.channels.get("testing")

                waitUntil(timeout: testTimeout) { done in
                    subscribeChannel.attach() { _ in
                        done()
                    }
                }

                let expectedResults = [Int](1...50)
                
                waitUntil(timeout: testTimeout) { done in
                    var index = 0
                    subscribeChannel.subscribe({ message in
                        let value = expectedResults[index]
                        let receivedValue = message.name
                        expect(receivedValue).to(equal(String(value)))
                        index += 1
                        if (receivedValue == String(describing: expectedResults.last!)) {
                            done()
                        }
                    })
                    for i in expectedResults {
                        sendChannel.publish(String(i), data: nil)
                    }
                }
            }

            class AblyManager {
                static let sharedClient = ARTRealtime(options: { $0.autoConnect = false; return $0 }(ARTClientOptions(key: "xxxx:xxxx")))
            }

            // Issue https://github.com/ably/ably-cocoa/issues/640
            it("should dispatch in user queue when removing an observer") {
                class Foo {
                    init() {
                        AblyManager.sharedClient.channels.get("foo").subscribe { _ in
                            // keep reference
                            self.update()
                        }
                    }
                    func update() {
                    }
                    deinit {
                        AblyManager.sharedClient.channels.get("foo").unsubscribe()
                    }
                }

                var foo: Foo? = Foo()
                expect(foo).toNot(beNil())
                foo = nil
                AblyManager.sharedClient.channels.get("foo").unsubscribe()
            }

            it("should never register any connection listeners for internal use with the public EventEmitter") {
                let options = AblyTests.commonAppSetup()
                options.autoConnect = false
                let client = ARTRealtime(options: options)
                defer { client.dispose(); client.close() }

                client.connect()
                client.close() // Before it connects; this registers a listener on the internal event emitter.
                expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connecting))
                client.connection.off()
                // If we didn't have a separate internal event emitter, the line above would unregister
                // the listener, and the next lines would fail, because we would never move to 
                // CLOSED, because we do that on the internal event listener registered when
                // we called close().
                expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connecting)) // Still connecting...
                expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.closed), timeout: testTimeout)
            }

            it("should never register any message and channel listeners for internal use with the public EventEmitter") {
                let options = AblyTests.commonAppSetup()
                let client = ARTRealtime(options: options)
                defer { client.dispose(); client.close() }

                let channel = client.channels.get("test")
                waitUntil(timeout: testTimeout) { done in
                    channel.attach { _ in
                        done()
                    }
                }
                if channel.state != .attached {
                    fail("Channel is not attached")
                    return
                }

                client.internal.onDisconnected()
                expect(client.connection.state).to(equal(.disconnected))

                // If we now send a message through the channel, it will be queued and the channel
                // should register a listener in the connection's _internal_ event emitter.
                // If we call client.connection.off(), reconnect, and never get the message ACK,
                // we probably weren't using the internal event emitter but the public one.

                client.connection.off()

                waitUntil(timeout: testTimeout) { done in
                    channel.publish("test", data: nil) { err in
                        expect(err).to(beNil())
                        done()
                    }
                    client.connect()
                }
            }
            
            xit("moves to DISCONNECTED on an unexpected normal WebSocket close") {
                let options = AblyTests.commonAppSetup()
                let client = ARTRealtime(options: options)
                defer { client.dispose(); client.close() }
                
                var received = false
                client.channels.get("test").subscribe() { msg in
                    received = true
                }

                expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
                
                let ws = (client.internal.transport! as! ARTWebSocketTransport).websocket!
                ws.close(withCode: 1000, reason: "test")
                
                expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.disconnected), timeout: testTimeout)
                expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
                
                client.channels.get("test").publish(nil, data: "test")
                
                expect(received).toEventually(beTrue(), timeout: testTimeout)
            }
        }
        
        // RSL1i
        context("If the total size of message(s) exceeds the maxMessageSize") {
            let channelName = "test-message-size"
            let presenceData = buildStringThatExceedMaxMessageSize()
            let clientId = "testMessageSizeClientId"
            
            it("the client library should reject the publish and indicate an error") {
                let options = AblyTests.commonAppSetup()
                let client = ARTRealtime(options: options)
                let channel = client.channels.get(channelName)
                let messages = buildMessagesThatExceedMaxMessageSize()
                
                waitUntil(timeout: testTimeout, action: { done in
                    // Wait for connected so that maxMessageSize is loaded from connection details
                    client.connection.once(.connected) { _ in
                        channel.publish(messages, callback: { err in
                            expect(err?.code).to(equal(40009))
                            expect(err?.message).to(contain("maximum message length exceeded"))
                            done()
                        })
                    }
                })
            }
            
            it("the client library should reject also presence messages (enter)") {
                let options = AblyTests.commonAppSetup()
                options.clientId = clientId
                let client = ARTRealtime(options: options)
                let channel = client.channels.get(channelName)
                
                waitUntil(timeout: testTimeout, action: { done in
                    client.connection.once(.connected) { _ in
                        channel.presence.enter(presenceData, callback: { err in
                            expect(err?.code).to(equal(40009))
                            expect(err?.message).to(contain("maximum message length exceeded"))
                            done()
                        })
                    }
                })
            }
            
            it("the client library should reject also presence messages (leave)") {
                let options = AblyTests.commonAppSetup()
                options.clientId = clientId
                let client = ARTRealtime(options: options)
                let channel = client.channels.get(channelName)
                
                waitUntil(timeout: testTimeout, action: { done in
                    client.connection.once(.connected) { _ in
                        channel.presence.leave(presenceData, callback: { err in
                            expect(err?.code).to(equal(40009))
                            expect(err?.message).to(contain("maximum message length exceeded"))
                            done()
                        })
                    }
                })
            }
            
            it("the client library should reject also presence messages (update)") {
                let options = AblyTests.commonAppSetup()
                options.clientId = clientId
                let client = ARTRealtime(options: options)
                let channel = client.channels.get(channelName)
                
                waitUntil(timeout: testTimeout, action: { done in
                    client.connection.once(.connected) { _ in
                        channel.presence.update(presenceData, callback: { err in
                            expect(err?.code).to(equal(40009))
                            expect(err?.message).to(contain("maximum message length exceeded"))
                            done()
                        })
                    }
                })
            }
            
            it("the client library should reject also presence messages (updateClient)") {
                let options = AblyTests.commonAppSetup()
                options.clientId = clientId
                let client = ARTRealtime(options: options)
                let channel = client.channels.get(channelName)
                
                waitUntil(timeout: testTimeout, action: { done in
                    client.connection.once(.connected) { _ in
                        channel.presence.updateClient(clientId, data: presenceData, callback: { err in
                            expect(err?.code).to(equal(40009))
                            expect(err?.message).to(contain("maximum message length exceeded"))
                            done()
                        })
                    }
                })
            }
            
            it("the client library should reject also presence messages (leaveClient)") {
                let options = AblyTests.commonAppSetup()
                options.clientId = clientId
                let client = ARTRealtime(options: options)
                let channel = client.channels.get(channelName)
                
                waitUntil(timeout: testTimeout, action: { done in
                    client.connection.once(.connected) { _ in
                        channel.presence.leaveClient(clientId, data: presenceData, callback: { err in
                            expect(err?.code).to(equal(40009))
                            expect(err?.message).to(contain("maximum message length exceeded"))
                            done()
                        })
                    }
                })
            }
        }
    }
}
