//
//  Auth.swift
//  ably
//
//  Created by Yavor Georgiev on 28.08.15.
//  Copyright (c) 2015 г. Ably. All rights reserved.
//

import Ably
import Ably.Private
import Nimble
import Quick
import Aspects

class Auth : QuickSpec {
    override func spec() {
        
        struct ExpectedTokenParams {
            static let clientId = "client_from_params"
            static let ttl = 1.0
            static let capability = "{\"cansubscribe:*\":[\"subscribe\"]}"
        }
        
        var testHTTPExecutor: TestProxyHTTPExecutor!

        describe("Basic") {

            // RSA1
            it("should work over HTTPS only") {
                let clientOptions = AblyTests.setupOptions(AblyTests.jsonRestOptions)
                clientOptions.tls = false

                expect{ ARTRest(options: clientOptions) }.to(raiseException())
            }

            // RSA11
            it("should send the API key in the Authorization header") {
                let options = AblyTests.setupOptions(AblyTests.jsonRestOptions)
                let client = ARTRest(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                client.internal.httpExecutor = testHTTPExecutor
                
                waitUntil(timeout: testTimeout) { done in
                    client.channels.get("test").publish(nil, data: "message") { error in
                        done()
                    }
                }

                let key64 = "\(client.internal.options.key!)"
                    .data(using: .utf8)!
                    .base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0))
                                
                let expectedAuthorization = "Basic \(key64)"
                
                guard let request = testHTTPExecutor.requests.first else {
                    fail("No request found")
                    return
                }
                
                let authorization = request.allHTTPHeaderFields?["Authorization"]
                
                expect(authorization).to(equal(expectedAuthorization))
            }

            // RSA2
            it("should be default when an API key is set") {
                let client = ARTRest(options: ARTClientOptions(key: "fake:key"))

                expect(client.auth.internal.method).to(equal(ARTAuthMethod.basic))
            }
        }

        describe("Token") {
            
            // RSA3
            context("token auth") {
                // RSA3a
                it("should work over HTTP") {
                    let options = AblyTests.clientOptions(requestToken: true)
                    options.tls = false
                    let clientHTTP = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    clientHTTP.internal.httpExecutor = testHTTPExecutor
                    
                    waitUntil(timeout: testTimeout) { done in
                        clientHTTP.channels.get("test").publish(nil, data: "message") { error in
                            done()
                        }
                    }

                    guard let request = testHTTPExecutor.requests.first else {
                        fail("No request found")
                        return
                    }
                    guard let url = request.url else {
                        fail("Request is invalid")
                        return
                    }
                    expect(url.scheme).to(equal("http"), description: "No HTTP support")
                }

                it("should work over HTTPS") {
                    let options = AblyTests.clientOptions(requestToken: true)
                    options.tls = true
                    let clientHTTPS = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    clientHTTPS.internal.httpExecutor = testHTTPExecutor
                    
                    waitUntil(timeout: testTimeout) { done in
                        clientHTTPS.channels.get("test").publish(nil, data: "message") { error in
                            done()
                        }
                    }

                    guard let request = testHTTPExecutor.requests.first else {
                        fail("No request found")
                        return
                    }
                    guard let url = request.url else {
                        fail("Request is invalid")
                        return
                    }
                    expect(url.scheme).to(equal("https"), description: "No HTTPS support")
                }

                // RSA3b
                it("should send the token in the Authorization header") {
                    let options = AblyTests.clientOptions()
                    options.token = getTestToken()

                    let client = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    
                    waitUntil(timeout: testTimeout) { done in
                        client.channels.get("test").publish(nil, data: "message") { error in
                            done()
                        }
                    }

                    guard let currentToken = client.internal.options.token else {
                        fail("No access token")
                        return
                    }

                    let expectedAuthorization = "Bearer \(encodeBase64(currentToken))"
                    
                    guard let request = testHTTPExecutor.requests.first else {
                        fail("No request found")
                        return
                    }

                    let authorization = request.allHTTPHeaderFields?["Authorization"]

                    expect(authorization).to(equal(expectedAuthorization))
                }
                
                // RSA3c
                it("should send the token in the Authorization header") {
                    let options = AblyTests.clientOptions()
                    options.token = getTestToken()
                    options.autoConnect = false

                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    client.internal.setTransport(TestProxyTransport.self)
                    client.connect()

                    if let transport = client.internal.transport as? TestProxyTransport, let query = transport.lastUrl?.query {
                        expect(query).to(haveParam("accessToken", withValue: client.auth.tokenDetails?.token ?? ""))
                    }
                    else {
                        XCTFail("MockTransport is not working")
                    }
                }
            }

            // RSA4
            context("authentication method") {
                for (caseName, caseSetter) in AblyTests.authTokenCases {
                    it("should be default auth method when \(caseName) is set") {
                        let options = ARTClientOptions()
                        caseSetter(options)

                        let client = ARTRest(options: options)

                        expect(client.auth.internal.method).to(equal(ARTAuthMethod.token))
                    }
                }

                // RSA4a
                it("should indicate an error and not retry the request when the server responds with a token error and there is no way to renew the token") {
                    let options = AblyTests.clientOptions()
                    options.token = getTestToken()

                    let rest = ARTRest(options: options)
                    // No means to renew the token is provided
                    expect(rest.internal.options.key).to(beNil())
                    expect(rest.internal.options.authCallback).to(beNil())
                    expect(rest.internal.options.authUrl).to(beNil())
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    rest.internal.httpExecutor = testHTTPExecutor

                    let channel = rest.channels.get("test")

                    testHTTPExecutor.simulateIncomingServerErrorOnNextRequest(40141, description: "token revoked")
                    waitUntil(timeout: testTimeout) { done in
                        channel.publish("message", data: nil) { error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(UInt(error.code)).to(equal(ARTState.requestTokenFailed.rawValue))
                            done()
                        }
                    }
                }

                // RSA4a
                it("should transition the connection to the FAILED state when the server responds with a token error and there is no way to renew the token") {
                    let options = AblyTests.clientOptions()
                    options.tokenDetails = getTestTokenDetails(ttl: 0.1)
                    options.autoConnect = false

                    // Token will expire, expecting 40142
                    waitUntil(timeout: testTimeout) { done in
                        delay(0.2) { done() }
                    }

                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }
                    // No means to renew the token is provided
                    expect(realtime.internal.options.key).to(beNil())
                    expect(realtime.internal.options.authCallback).to(beNil())
                    expect(realtime.internal.options.authUrl).to(beNil())
                    realtime.internal.setTransport(TestProxyTransport.self)

                    let channel = realtime.channels.get("test")

                    waitUntil(timeout: testTimeout.multiplied(by: 2)) { done in
                        realtime.connect()
                        channel.publish("message", data: nil) { error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error.code).to(equal(40142))
                            expect(realtime.connection.state).to(equal(ARTRealtimeConnectionState.failed))
                            done()
                        }
                    }
                }
                
                // RSA4b
                it("on token error, reissues token and retries REST requests") {
                    var authCallbackCalled = 0

                    let options = AblyTests.commonAppSetup()
                    options.authCallback = { _, callback in
                        authCallbackCalled += 1
                        getTestTokenDetails { token, err in
                            callback(token, err)
                        }
                    }

                    let rest = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    rest.internal.httpExecutor = testHTTPExecutor

                    let channel = rest.channels.get("test")

                    testHTTPExecutor.simulateIncomingServerErrorOnNextRequest(40141, description: "token revoked")
                    
                    waitUntil(timeout: testTimeout) { done in
                        channel.publish("message", data: nil) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    // First request and a second attempt
                    expect(testHTTPExecutor.requests).to(haveCount(2))
                    
                    // First token issue, and then reissue on token error.
                    expect(authCallbackCalled).to(equal(2))
                }

                // RSA4b
                it("in REST, if the token creation failed or the subsequent request with the new token failed due to a token error, then the request should result in an error") {
                    let options = AblyTests.commonAppSetup()
                    options.useTokenAuth = true

                    let rest = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    rest.internal.httpExecutor = testHTTPExecutor

                    let channel = rest.channels.get("test")

                    testHTTPExecutor.setListenerAfterRequest({ _ in
                        testHTTPExecutor.simulateIncomingServerErrorOnNextRequest(40141, description: "token revoked")
                    })

                    testHTTPExecutor.simulateIncomingServerErrorOnNextRequest(40141, description: "token revoked")
                    waitUntil(timeout: testTimeout) { done in
                        channel.publish("message", data: nil) { error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error.code).to(equal(40141))
                            done()
                        }
                    }

                    // First request and a second attempt
                    expect(testHTTPExecutor.requests).to(haveCount(2))
                }

                // RSA4b
                it("in Realtime, if the token creation failed then the connection should move to the DISCONNECTED state and reports the error") {
                    let options = AblyTests.commonAppSetup()
                    options.authCallback = { tokenParams, completion in
                        completion(nil, NSError(domain: NSURLErrorDomain, code: -1003, userInfo: [NSLocalizedDescriptionKey: "A server with the specified hostname could not be found."]))
                    }
                    options.autoConnect = false

                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }

                    waitUntil(timeout: testTimeout) { done in
                        realtime.connection.once(.failed) { _ in
                            fail("Should not reach Failed state"); done(); return
                        }
                        realtime.connection.once(.disconnected) { stateChange in
                            guard let errorInfo = stateChange?.reason else {
                                fail("ErrorInfo is nil"); done(); return
                            }
                            expect(errorInfo.message).to(contain("server with the specified hostname could not be found"))
                            done()
                        }
                        realtime.connect()
                    }
                }

                // RSA4b
                it("in Realtime, if the connection fails due to a terminal token error, then the connection should move to the FAILED state and reports the error") {
                    let options = AblyTests.commonAppSetup()
                    options.authCallback = { tokenParams, completion in
                        getTestToken() { token in
                            let invalidToken = String(token.reversed())
                            completion(invalidToken as ARTTokenDetailsCompatible?, nil)
                        }
                    }
                    options.autoConnect = false

                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }

                    waitUntil(timeout: testTimeout) { done in
                        realtime.connection.once(.failed) { stateChange in
                            guard let errorInfo = stateChange?.reason else {
                                fail("ErrorInfo is nil"); done(); return
                            }
                            expect(errorInfo.message).to(contain("No application found with id"))
                            done()
                        }
                        realtime.connection.once(.disconnected) { _ in
                            fail("Should not reach Disconnected state"); done(); return
                        }
                        realtime.connect()
                    }
                }

                // RSA4b1
                context("local token validity check") {
                    it("should be done if queryTime is true and local time is in sync with server") {
                        let options = AblyTests.commonAppSetup()
                        let testKey = options.key!

                        let tokenDetails = getTestTokenDetails(key: testKey, ttl: 5.0, queryTime: true)

                        options.queryTime = true
                        options.tokenDetails = tokenDetails
                        options.key = nil

                        let rest = ARTRest(options: options)
                        let proxyHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)

                        // Sync server time offset
                        let authOptions = ARTAuthOptions(key: testKey)
                        authOptions.queryTime = true
                        waitUntil(timeout: testTimeout) { done in
                            rest.auth.createTokenRequest(nil, options: authOptions, callback: { tokenRequest, error in
                                expect(error).to(beNil())
                                expect(tokenRequest).toNot(beNil())
                                done()
                            })
                        }

                        // Let the token expire
                        waitUntil(timeout: testTimeout) { done in
                            delay(5.0) {
                                done()
                            }
                        }

                        expect(rest.auth.internal.timeOffset).toNot(beNil())

                        rest.internal.httpExecutor = proxyHTTPExecutor
                        waitUntil(timeout: testTimeout) { done in
                            rest.channels.get("foo").history { _, error in
                                guard let error = error else {
                                    fail("Error is nil"); done(); return
                                }
                                expect((error ).code).to(equal(Int(ARTState.requestTokenFailed.rawValue)))
                                expect(error.message).to(contain("no means to renew the token is provided"))

                                expect(proxyHTTPExecutor.requests.count).to(equal(0))
                                done()
                            }
                        }

                        expect(rest.auth.tokenDetails).toNot(beNil())
                    }

                    it("should NOT be done if queryTime is false and local time is NOT in sync with server") {
                        let options = AblyTests.commonAppSetup()
                        let testKey = options.key!

                        let tokenDetails = getTestTokenDetails(key: testKey, ttl: 5.0, queryTime: true)

                        options.queryTime = false
                        options.tokenDetails = tokenDetails
                        options.key = nil

                        let rest = ARTRest(options: options)
                        let proxyHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                        rest.internal.httpExecutor = proxyHTTPExecutor

                        // No server time offset
                        rest.auth.internal.clearTimeOffset()

                        // Let the token expire
                        waitUntil(timeout: testTimeout) { done in
                            delay(5.0) {
                                done()
                            }
                        }

                        waitUntil(timeout: testTimeout) { done in
                            rest.channels.get("foo").history { _, error in
                                guard let error = error else {
                                    fail("Error is nil"); done(); return
                                }
                                expect((error ).code).to(equal(Int(ARTState.requestTokenFailed.rawValue)))
                                expect(error.message).to(contain("no means to renew the token is provided"))
                                expect(proxyHTTPExecutor.requests.count).to(equal(1))
                                expect(proxyHTTPExecutor.responses.count).to(equal(1))
                                guard let response = proxyHTTPExecutor.responses.first else {
                                    fail("Response is nil"); done(); return
                                }
                                expect(response.value(forHTTPHeaderField: "X-Ably-Errorcode")).to(equal("40142"))
                                done()
                            }
                        }
                    }
                }

                // RSA4d
                it("if a request by a realtime client to an authUrl results in an HTTP 403 the client library should transition to the FAILED state") {
                    let options = AblyTests.clientOptions()
                    options.autoConnect = false
                    options.authUrl = URL(string: "https://echo.ably.io/respondwith?status=403")!
                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }
                    
                    waitUntil(timeout: testTimeout) { done in
                        realtime.connection.once(.failed) { stateChange in
                            expect(stateChange?.reason?.code).to(equal(80019))
                            expect(stateChange?.reason?.statusCode).to(equal(403))
                            done()
                        }
                        realtime.connect()
                    }
                }
                
                // RSA4d
                it("if an authCallback results in an HTTP 403 the client library should transition to the FAILED state") {
                    let options = AblyTests.clientOptions()
                    options.autoConnect = false
                    var authCallbackHasBeenInvoked = false
                    options.authCallback = { tokenParams, completion in
                        authCallbackHasBeenInvoked = true
                        completion(nil, ARTErrorInfo(domain: "io.ably.cocoa", code: 40300, userInfo: ["ARTErrorInfoStatusCode": 403]))
                    }
                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }
                    
                    waitUntil(timeout: testTimeout) { done in
                        realtime.connection.once(.failed) { stateChange in
                            expect(authCallbackHasBeenInvoked).to(beTrue())
                            expect(stateChange?.reason?.code).to(equal(80019))
                            expect(stateChange?.reason?.statusCode).to(equal(403))
                            done()
                        }
                        realtime.connect()
                    }
                }
            }
            
            // RSA14
            context("options") {
                // Cases:
                //  - useTokenAuth is specified and thus a key is not provided
                //  - authCallback and authUrl are both specified
                let cases: [String: (ARTAuthOptions) -> ()] = [
                    "useTokenAuth and no key":{ $0.useTokenAuth = true },
                    "authCallback and authUrl":{ $0.authCallback = { params, callback in /*nothing*/ }; $0.authUrl = URL(string: "http://auth.ably.io") }
                ]
                
                for (caseName, caseSetter) in cases {
                    it("should stop client when \(caseName) occurs") {
                        let options = ARTClientOptions()
                        caseSetter(options)
                        
                        expect{ ARTRest(options: options) }.to(raiseException())
                    }
                }

                // RSA4c
                context("if an attempt by the realtime client library to authenticate is made using the authUrl or authCallback") {

                    context("the request to authUrl fails") {

                        // RSA4c1 & RSA4c2
                        it("if the connection is CONNECTING, then the connection attempt should be treated as unsuccessful") {
                            let options = AblyTests.clientOptions()
                            options.autoConnect = false
                            options.authUrl = URL(string: "http://echo.ably.io")!
                            let realtime = ARTRealtime(options: options)
                            defer { realtime.dispose(); realtime.close() }

                            waitUntil(timeout: testTimeout) { done in
                                realtime.connection.once(.disconnected) { stateChange in
                                    guard let stateChange = stateChange else {
                                        fail("ConnectionStateChange is nil"); done(); return
                                    }
                                    expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connecting))
                                    guard let errorInfo = stateChange.reason else {
                                        fail("ErrorInfo is nil"); done(); return
                                    }
                                    expect(errorInfo.code) == 80019
                                    done()
                                }
                                realtime.connect()
                            }

                            guard let errorInfo = realtime.connection.errorReason else {
                                fail("ErrorInfo is empty"); return
                            }
                            expect(errorInfo.code) == 80019
                            expect(errorInfo.message).to(contain("body param is required"))
                        }

                        // RSA4c3
                        it("if the connection is CONNECTED, then the connection should remain CONNECTED") {
                            let token = getTestToken()
                            let options = AblyTests.clientOptions()
                            options.authUrl = URL(string: "http://echo.ably.io")!
                            options.authParams = [URLQueryItem]()
                            options.authParams?.append(URLQueryItem(name: "type", value: "text"))
                            options.authParams?.append(URLQueryItem(name: "body", value: token))

                            let realtime = ARTRealtime(options: options)
                            defer { realtime.dispose(); realtime.close() }

                            waitUntil(timeout: testTimeout) { done in
                                realtime.connection.once(.connected) { stateChange in
                                    expect(stateChange?.reason).to(beNil())
                                    done()
                                }
                            }

                            // Token reauth will fail
                            realtime.internal.options.authParams = [URLQueryItem]()

                            // Inject AUTH
                            let authMessage = ARTProtocolMessage()
                            authMessage.action = ARTProtocolMessageAction.auth
                            realtime.internal.transport?.receive(authMessage)

                            expect(realtime.connection.errorReason).toEventuallyNot(beNil(), timeout: testTimeout)
                            guard let errorInfo = realtime.connection.errorReason else {
                                fail("ErrorInfo is empty"); return
                            }
                            expect(errorInfo.code) == 80019
                            expect(errorInfo.message).to(contain("body param is required"))

                            expect(realtime.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                        }
                    }

                    context("the request to authCallback fails") {

                        // RSA4c1 & RSA4c2
                        it("if the connection is CONNECTING, then the connection attempt should be treated as unsuccessful") {
                            let options = AblyTests.clientOptions()
                            options.autoConnect = false
                            options.authCallback = { tokenParams, completion in
                                completion(nil, NSError(domain: NSURLErrorDomain, code: -1003, userInfo: [NSLocalizedDescriptionKey: "A server with the specified hostname could not be found."]))
                            }
                            let realtime = ARTRealtime(options: options)
                            defer { realtime.dispose(); realtime.close() }

                            waitUntil(timeout: testTimeout) { done in
                                realtime.connection.once(.disconnected) { stateChange in
                                    guard let stateChange = stateChange else {
                                        fail("ConnectionStateChange is nil"); done(); return
                                    }
                                    expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connecting))
                                    guard let errorInfo = stateChange.reason else {
                                        fail("ErrorInfo is nil"); done(); return
                                    }
                                    expect(errorInfo.code) == 80019
                                    done()
                                }
                                realtime.connect()
                            }

                            expect(realtime.connection.state).toEventually(equal(ARTRealtimeConnectionState.disconnected), timeout: testTimeout)
                            guard let errorInfo = realtime.connection.errorReason else {
                                fail("ErrorInfo is empty"); return
                            }
                            expect(errorInfo.code) == 80019
                            expect(errorInfo.message).to(contain("hostname could not be found"))
                        }

                        // RSA4c3
                        it("if the connection is CONNECTED, then the connection should remain CONNECTED") {
                            let options = AblyTests.clientOptions()
                            options.authCallback = { tokenParams, completion in
                                getTestTokenDetails(completion: completion)
                            }
                            let realtime = ARTRealtime(options: options)
                            defer { realtime.dispose(); realtime.close() }

                            waitUntil(timeout: testTimeout) { done in
                                realtime.connection.once(.connected) { stateChange in
                                    expect(stateChange?.reason).to(beNil())
                                    done()
                                }
                            }

                            // Token should renew and fail
                            realtime.internal.options.authCallback = { tokenParams, completion in
                                completion(nil, NSError(domain: NSURLErrorDomain, code: -1003, userInfo: [NSLocalizedDescriptionKey: "A server with the specified hostname could not be found."]))
                            }

                            // Inject AUTH
                            let authMessage = ARTProtocolMessage()
                            authMessage.action = ARTProtocolMessageAction.auth
                            realtime.internal.transport?.receive(authMessage)

                            expect(realtime.connection.errorReason).toEventuallyNot(beNil(), timeout: testTimeout)
                            guard let errorInfo = realtime.connection.errorReason else {
                                fail("ErrorInfo is empty"); return
                            }
                            expect(errorInfo.code) == 80019
                            expect(errorInfo.message).to(contain("hostname could not be found"))

                            expect(realtime.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                        }
                    }

                    context("the provided token is in an invalid format") {

                        // RSA4c1 & RSA4c2
                        it("if the connection is CONNECTING, then the connection attempt should be treated as unsuccessful") {
                            let options = AblyTests.clientOptions()
                            options.autoConnect = false
                            options.authUrl = URL(string: "http://echo.ably.io")!
                            options.authParams = [URLQueryItem]()
                            options.authParams?.append(URLQueryItem(name: "type", value: "json"))
                            let invalidTokenFormat = "{secret_token:xxx}"
                            options.authParams?.append(URLQueryItem(name: "body", value: invalidTokenFormat))

                            let realtime = ARTRealtime(options: options)
                            defer { realtime.dispose(); realtime.close() }

                            waitUntil(timeout: testTimeout) { done in
                                realtime.connection.once(.disconnected) { stateChange in
                                    guard let stateChange = stateChange else {
                                        fail("ConnectionStateChange is nil"); done(); return
                                    }
                                    expect(stateChange.previous).to(equal(ARTRealtimeConnectionState.connecting))
                                    guard let errorInfo = stateChange.reason else {
                                        fail("ErrorInfo is nil"); done(); return
                                    }
                                    expect(errorInfo.code) == 80019
                                    done()
                                }
                                realtime.connect()
                            }

                            guard let errorInfo = realtime.connection.errorReason else {
                                fail("ErrorInfo is empty"); return
                            }
                            expect(errorInfo.code) == 80019
                            expect(errorInfo.message).to(contain("content response cannot be used for token request"))

                            expect(realtime.connection.state).toEventually(equal(ARTRealtimeConnectionState.disconnected), timeout: testTimeout)
                        }

                        // RSA4c3
                        it("if the connection is CONNECTED, then the connection should remain CONNECTED") {
                            let options = AblyTests.clientOptions()
                            options.authUrl = URL(string: "http://echo.ably.io")!
                            options.authParams = [URLQueryItem]()
                            options.authParams?.append(URLQueryItem(name: "type", value: "text"))

                            let token = getTestToken()
                            options.authParams?.append(URLQueryItem(name: "body", value: token))

                            let realtime = ARTRealtime(options: options)
                            defer { realtime.dispose(); realtime.close() }

                            waitUntil(timeout: testTimeout) { done in
                                realtime.connection.once(.connected) { stateChange in
                                    expect(stateChange?.reason).to(beNil())
                                    done()
                                }
                            }

                            // Token should renew and fail
                            waitUntil(timeout: testTimeout) { done in
                                realtime.unwrapAsync { realtime in
                                    realtime.options.authParams = [URLQueryItem]()
                                    realtime.options.authParams?.append(URLQueryItem(name: "type", value: "json"))
                                    let invalidTokenFormat = "{secret_token:xxx}"
                                    realtime.options.authParams?.append(URLQueryItem(name: "body", value: invalidTokenFormat))
                                    done()
                                }
                            }

                            realtime.connection.on() { stateChange in
                                guard let stateChange = stateChange else {
                                    fail("ConnectionStateChange should not be nil"); return
                                }
                                if stateChange.current != .connected {
                                    fail("Connection should remain connected")
                                }
                            }

                            // Inject AUTH
                            let authMessage = ARTProtocolMessage()
                            authMessage.action = ARTProtocolMessageAction.auth
                            realtime.internal.transport?.receive(authMessage)

                            expect(realtime.connection.errorReason).toEventuallyNot(beNil(), timeout: testTimeout)
                            guard let errorInfo = realtime.connection.errorReason else {
                                fail("ErrorInfo is empty"); return
                            }
                            expect(errorInfo.code) == 80019
                            expect(errorInfo.message).to(contain("content response cannot be used for token request"))

                            expect(realtime.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                        }
                    }

                    context("the attempt times out after realtimeRequestTimeout") {
                        // RSA4c1 & RSA4c2
                        it("if the connection is CONNECTING, then the connection attempt should be treated as unsuccessful") {
                            let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
                            defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
                            ARTDefault.setRealtimeRequestTimeout(0.5)

                            let options = AblyTests.clientOptions()
                            options.autoConnect = false
                            options.authCallback = { tokenParams, completion in
                                // Ignore `completion` closure to force a time out
                            }

                            let realtime = ARTRealtime(options: options)
                            defer { realtime.dispose(); realtime.close() }

                            waitUntil(timeout: testTimeout) { done in
                                realtime.connection.once(.disconnected) { stateChange in
                                    guard let stateChange = stateChange else {
                                        fail("ConnectionStateChange is nil"); done(); return
                                    }
                                    guard let errorInfo = stateChange.reason else {
                                        fail("ErrorInfo is nil"); done(); return
                                    }
                                    expect(errorInfo.code) == 80019
                                    done()
                                }
                                realtime.connect()
                            }

                            guard let errorInfo = realtime.connection.errorReason else {
                                fail("ErrorInfo is empty"); return
                            }
                            expect(errorInfo.code) == 80019
                            expect(errorInfo.message).to(contain("timed out"))

                            expect(realtime.connection.state).toEventually(equal(ARTRealtimeConnectionState.disconnected), timeout: testTimeout)
                        }

                        // RSA4c3
                        it("if the connection is CONNECTED, then the connection should remain CONNECTED") {
                            let options = AblyTests.clientOptions()
                            options.autoConnect = false
                            options.authCallback = { tokenParams, completion in
                                getTestTokenDetails(completion: completion)
                            }

                            let realtime = ARTRealtime(options: options)
                            defer { realtime.dispose(); realtime.close() }

                            waitUntil(timeout: testTimeout) { done in
                                realtime.connection.once(.connected) { stateChange in
                                    expect(stateChange?.reason).to(beNil())
                                    done()
                                }
                                realtime.connect()
                            }

                            let previousRealtimeRequestTimeout = ARTDefault.realtimeRequestTimeout()
                            defer { ARTDefault.setRealtimeRequestTimeout(previousRealtimeRequestTimeout) }
                            ARTDefault.setRealtimeRequestTimeout(0.5)

                            // Token should renew and fail
                            realtime.internal.options.authCallback = { tokenParams, completion in
                                // Ignore `completion` closure to force a time out
                            }

                            // Inject AUTH
                            let authMessage = ARTProtocolMessage()
                            authMessage.action = ARTProtocolMessageAction.auth
                            waitUntil(timeout: testTimeout) { done in
                                realtime.unwrapAsync { realtime in
                                    realtime.transport?.receive(authMessage)
                                    done()
                                }
                            }

                            expect(realtime.connection.errorReason).toEventuallyNot(beNil(), timeout: testTimeout)
                            guard let errorInfo = realtime.connection.errorReason else {
                                fail("ErrorInfo is empty"); return
                            }
                            expect(errorInfo.code) == 80019
                            expect(errorInfo.message).to(contain("timed out"))

                            expect(realtime.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                        }
                    }
                }
            }

            // RSA15
            context("token auth and clientId") {
                // RSA15a
                context("should check clientId consistency") {

                    it("on rest") {
                        let expectedClientId = "client_string"
                        let options = AblyTests.commonAppSetup()
                        options.useTokenAuth = true
                        options.clientId = expectedClientId

                        let client = ARTRest(options: options)
                        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                        client.internal.httpExecutor = testHTTPExecutor

                        waitUntil(timeout: testTimeout) { done in
                            // Token
                            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                                expect(error).to(beNil())
                                expect(client.auth.internal.method).to(equal(ARTAuthMethod.token))
                                guard let tokenDetails = tokenDetails else {
                                    fail("TokenDetails is nil"); done(); return
                                }
                                expect(tokenDetails.clientId).to(equal(expectedClientId))
                                done()
                            }
                        }

                        switch extractBodyAsMsgPack(testHTTPExecutor.requests.first) {
                        case .failure(let error):
                            XCTFail(error)
                        case .success(let httpBody):
                            guard let requestedClientId = httpBody.unbox["clientId"] as? String else { XCTFail("No clientId field in HTTPBody"); return }
                            expect(requestedClientId).to(equal(expectedClientId))
                        }
                    }

                    it("on realtime") {
                        let expectedClientId = "client_string"
                        let options = AblyTests.setupOptions(AblyTests.jsonRestOptions)
                        options.clientId = expectedClientId
                        options.autoConnect = false

                        let client = ARTRealtime(options: options)
                        defer { client.dispose(); client.close() }
                        client.internal.setTransport(TestProxyTransport.self)
                        client.connect()

                        waitUntil(timeout: testTimeout) { done in
                            client.connection.on { stateChange in
                                let stateChange = stateChange!
                                let state = stateChange.current
                                let error = stateChange.reason
                                if state == .connected && error == nil {
                                    let currentChannel = client.channels.get("test")
                                    currentChannel.subscribe({ message in
                                        done()
                                    })
                                    currentChannel.publish(nil, data: "ping", callback:nil)
                                }
                            }
                        }

                        guard let transport = client.internal.transport as? TestProxyTransport else {
                            fail("Transport is nil"); return
                        }
                        guard let connectedMessage = transport.protocolMessagesReceived.filter({ $0.action == .connected }).last else {
                            XCTFail("No CONNECTED protocol action received"); return
                        }

                        // CONNECTED ProtocolMessage
                        expect(connectedMessage.connectionDetails!.clientId).to(equal(expectedClientId))
                    }

                    it("with wildcard") {
                        let options = AblyTests.setupOptions(AblyTests.jsonRestOptions)
                        options.clientId = "*"
                        expect{ ARTRest(options: options) }.to(raiseException())
                        expect{ ARTRealtime(options: options) }.to(raiseException())
                    }
                }
                
                // RSA15b
                it("should permit to be unauthenticated") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = nil
                    
                    let clientBasic = ARTRest(options: options)

                    waitUntil(timeout: testTimeout) { done in
                        // Basic
                        clientBasic.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(clientBasic.auth.clientId).to(beNil())
                            options.tokenDetails = tokenDetails
                            done()
                        }
                    }

                    let clientToken = ARTRest(options: options)

                    waitUntil(timeout: testTimeout) { done in
                        // Last TokenDetails
                        clientToken.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(clientToken.auth.clientId).to(beNil())
                            done()
                        }
                    }
                }
                
                // RSA15c
                context("Incompatible client") {

                    it("with Realtime, it should change the connection state to FAILED and emit an error") {
                        let options = AblyTests.commonAppSetup()
                        let wrongTokenDetails = getTestTokenDetails(clientId: "wrong")

                        options.clientId = "john"
                        options.autoConnect = false
                        options.authCallback = { tokenParams, completion in
                            completion(wrongTokenDetails, nil)
                        }
                        let realtime = ARTRealtime(options: options)
                        defer { realtime.close() }

                        waitUntil(timeout: testTimeout) { done in
                            realtime.connection.once(.failed) { stateChange in
                                expect(stateChange!.reason?.code).to(equal(40101))
                                expect(stateChange!.reason?.description.lowercased()).to(contain("invalid clientid for credentials"))
                                done()
                            }
                            realtime.connect()
                        }
                    }

                    it("with Rest, it should result in an appropriate error response") {
                        let options = AblyTests.commonAppSetup()
                        options.clientId = "john"
                        let rest = ARTRest(options: options)

                        waitUntil(timeout: testTimeout) { done in
                            rest.auth.requestToken(ARTTokenParams(clientId: "wrong"), with: nil) { tokenDetails, error in
                                let error = error as! ARTErrorInfo
                                expect(error.code).to(equal(40102))
                                expect(error.localizedDescription).to(contain("incompatible credentials"))
                                expect(tokenDetails).to(beNil())
                                done()
                            }
                        }
                    }
                }
            }
            
            // RSA5
            it("TTL should default to be omitted") {
                let tokenParams = ARTTokenParams()
                expect(tokenParams.ttl).to(beNil())
            }

            it("should URL query be correctly encoded") {
                let tokenParams = ARTTokenParams()
                tokenParams.capability = "{\"*\":[\"*\"]}"

                if #available(iOS 10.0, *) {
                    let dateFormatter = ISO8601DateFormatter()
                    tokenParams.timestamp = dateFormatter.date(from: "2016-10-08T22:31:00Z")
                }
                else {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy/MM/dd HH:mm zzz"
                    tokenParams.timestamp = dateFormatter.date(from: "2016/10/08 22:31 GMT")
                }

                let options = ARTClientOptions()
                options.authUrl = URL(string: "https://ably-test-suite.io")
                let rest = ARTRest(options: options)
                let request = rest.auth.internal.buildRequest(options, with: tokenParams)

                if let query = request.url?.query {
                    expect(query).to(haveParam("capability", withValue: "%7B%22*%22:%5B%22*%22%5D%7D"))
                    expect(query).to(haveParam("timestamp", withValue: "1475965860000"))
                }
                else {
                    fail("URL is empty")
                }
            }
            
            // RSA6
            it("should omit capability field if it is not specified") {
                let tokenParams = ARTTokenParams()
                expect(tokenParams.capability).to(beNil())
                
                let options = AblyTests.setupOptions(AblyTests.jsonRestOptions)
                let rest = ARTRest(options: options)
                let testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                rest.internal.httpExecutor = testHTTPExecutor

                waitUntil(timeout: testTimeout) { done in
                    // Token
                    rest.auth.requestToken(tokenParams, with: options) { tokenDetails, error in
                        if let e = error {
                            fail(e.localizedDescription); done(); return
                        }
                        expect(tokenParams.capability).to(beNil())
                        expect(tokenDetails?.capability).to(equal("{\"*\":[\"*\"]}"))
                        done()
                    }
                }

                switch extractBodyAsMsgPack(testHTTPExecutor.requests.first) {
                case .failure(let error):
                    fail(error)
                case .success(let httpBody):
                    expect(httpBody.unbox["capability"]).to(beNil())
                }
            }

            // RSA6
            it("should add capability field if the user specifies it") {
                let tokenParams = ARTTokenParams()
                tokenParams.capability = "{\"*\":[\"*\"]}"

                let options = AblyTests.setupOptions(AblyTests.jsonRestOptions)
                let rest = ARTRest(options: options)
                let testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                rest.internal.httpExecutor = testHTTPExecutor

                waitUntil(timeout: testTimeout) { done in
                    // Token
                    rest.auth.requestToken(tokenParams, with: options) { tokenDetails, error in
                        if let e = error {
                            fail(e.localizedDescription); done(); return
                        }
                        expect(tokenDetails?.capability).to(equal(tokenParams.capability))
                        done()
                    }
                }

                switch extractBodyAsMsgPack(testHTTPExecutor.requests.first) {
                case .failure(let error):
                    fail(error)
                case .success(let httpBody):
                    expect(httpBody.unbox["capability"] as? String).to(equal("{\"*\":[\"*\"]}"))
                }
            }
            
            // RSA7
            context("clientId and authenticated clients") {

                // RSA7a1
                it("should not pass clientId with published message") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "mary"
                    let rest = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    rest.internal.httpExecutor = testHTTPExecutor
                    let channel = rest.channels.get("RSA7a1")
                    waitUntil(timeout: testTimeout) { done in
                        channel.publish("foo", data: nil) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }
                    switch extractBodyAsMsgPack(testHTTPExecutor.requests.last) {
                    case .failure(let error):
                        fail(error)
                    case .success(let httpBody):
                        let message = httpBody.unbox
                        expect(message["clientId"]).to(beNil())
                        expect(message["name"] as? String).to(equal("foo"))
                    }
                }
                
                // RSA7a2
                it("should obtain a token if clientId is assigned") {
                    let options = AblyTests.setupOptions(AblyTests.jsonRestOptions)
                    options.clientId = "client_string"
                    
                    let client = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    
                    waitUntil(timeout: testTimeout) { done in
                        client.channels.get("test").publish(nil, data: "message") { error in
                            if let e = error {
                                XCTFail((e ).localizedDescription)
                            }
                            done()
                        }
                    }
                    
                    let authorization = testHTTPExecutor.requests.last?.allHTTPHeaderFields?["Authorization"] ?? ""
                    
                    expect(authorization).toNot(equal(""))
                }
                
                // RSA7a3
                it("should convenience clientId return a string") {
                    let clientOptions = AblyTests.setupOptions(AblyTests.jsonRestOptions)
                    clientOptions.clientId = "String"
                    
                    expect(ARTRest(options: clientOptions).internal.options.clientId).to(equal("String"))
                }

                // RSA7a4
                it("ClientOptions#clientId takes precendence when a clientId value is provided in both ClientOptions#clientId and ClientOptions#defaultTokenParams") {
                    let options = AblyTests.clientOptions()
                    options.clientId = "john"
                    options.authCallback = { tokenParams, completion in
                        expect(tokenParams.clientId).to(equal(options.clientId))
                        getTestToken(clientId: tokenParams.clientId) { token in
                            completion(token as ARTTokenDetailsCompatible?, nil)
                        }
                    }
                    options.defaultTokenParams = ARTTokenParams(clientId: "tester")
                    let client = ARTRest(options: options)
                    let channel = client.channels.get("test")

                    expect(client.auth.clientId).to(equal("john"))
                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "message") { error in
                            expect(error).to(beNil())
                            channel.history() { paginatedResult, error in
                                guard let result = paginatedResult else {
                                    fail("PaginatedResult is empty"); done(); return
                                }
                                guard let message = result.items.first else {
                                    fail("First message does not exist"); done(); return
                                }
                                expect(message.clientId).to(equal("john"))
                                done()
                            }
                        }
                    }
                }
                
                // RSA12
                context("Auth#clientId attribute is null") {

                    // RSA12a
                    it("identity should be anonymous for all operations") {
                        let options = AblyTests.commonAppSetup()
                        options.autoConnect = false
                        let realtime = AblyTests.newRealtime(options)
                        defer { realtime.dispose(); realtime.close() }
                        expect(realtime.auth.clientId).to(beNil())

                        waitUntil(timeout: testTimeout) { done in
                            realtime.connection.once(.connected) { stateChange in
                                expect(stateChange!.reason).to(beNil())
                                expect(realtime.auth.clientId).to(beNil())
                                done()
                            }
                            realtime.connect()
                            
                            let transport = realtime.internal.transport as! TestProxyTransport
                            transport.beforeProcessingReceivedMessage = { message in
                                if message.action == .connected {
                                    if let details = message.connectionDetails {
                                        details.clientId = nil
                                    }
                                }
                            }
                        }
                    }

                    // RSA12b
                    it("identity may change and become identified") {
                        let options = AblyTests.commonAppSetup()
                        options.autoConnect = false
                        options.token = getTestToken(clientId: "tester")
                        let realtime = ARTRealtime(options: options)
                        defer { realtime.dispose(); realtime.close() }
                        expect(realtime.auth.clientId).to(beNil())

                        waitUntil(timeout: testTimeout) { done in
                            realtime.connection.once(.connecting) { stateChange in
                                expect(stateChange!.reason).to(beNil())
                                expect(realtime.auth.clientId).to(beNil())
                            }
                            realtime.connection.once(.connected) { stateChange in
                                expect(stateChange!.reason).to(beNil())
                                expect(realtime.auth.clientId).to(equal("tester"))
                                done()
                            }
                            realtime.connect()
                        }
                    }

                }
                
                // RSA7b
                context("auth.clientId not null") {
                    // RSA7b1
                    it("when clientId attribute is assigned on client options") {
                        let clientOptions = AblyTests.setupOptions(AblyTests.jsonRestOptions)
                        clientOptions.clientId = "Exist"
                        
                        expect(ARTRest(options: clientOptions).auth.clientId).to(equal("Exist"))
                    }
                    
                    // RSA7b2
                    it("when tokenRequest or tokenDetails has clientId not null or wildcard string") {
                        let options = AblyTests.commonAppSetup()
                        options.clientId = "client_string"
                        options.useTokenAuth = true
                        
                        let client = ARTRest(options: options)
                        testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                        client.internal.httpExecutor = testHTTPExecutor
                        
                        // TokenDetails
                        waitUntil(timeout: testTimeout) { done in
                            // Token
                            client.auth.authorize(nil, options: nil) { token, error in
                                expect(error).to(beNil())
                                expect(client.auth.internal.method).to(equal(ARTAuthMethod.token))
                                expect(client.auth.clientId).to(equal(options.clientId))
                                done()
                            }
                        }
                        
                        // TokenRequest
                        switch extractBodyAsMsgPack(testHTTPExecutor.requests.last) {
                        case .failure(let error):
                            XCTFail(error)
                        case .success(let httpBody):
                            guard let requestedClientId = httpBody.unbox["clientId"] as? String else { XCTFail("No clientId field in HTTPBody"); return }
                            expect(client.auth.clientId).to(equal(requestedClientId))
                        }
                    }
                    
                    // RSA7b3
                    it("should CONNECTED ProtocolMessages contain a clientId") {
                        let options = AblyTests.clientOptions()
                        options.token = getTestToken(clientId: "john")
                        expect(options.clientId).to(beNil())
                        options.autoConnect = false
                        let realtime = AblyTests.newRealtime(options)
                        defer { realtime.dispose(); realtime.close() }

                        waitUntil(timeout: testTimeout) { done in
                            realtime.connection.once(.connected) { stateChange in
                                expect(stateChange!.reason).to(beNil())
                                expect(realtime.auth.clientId).to(equal("john"))

                                let transport = realtime.internal.transport as! TestProxyTransport
                                let connectedProtocolMessage = transport.protocolMessagesReceived.filter{ $0.action == .connected }[0]
                                expect(connectedProtocolMessage.connectionDetails!.clientId).to(equal("john"))
                                done()
                            }
                            realtime.connect()
                        }
                    }

                    // RSA7b4
                    it("client does not have an identity when a wildcard string '*' is present") {
                        let options = AblyTests.clientOptions()
                        options.token = getTestToken(clientId: "*")
                        let realtime = ARTRealtime(options: options)
                        defer { realtime.dispose(); realtime.close() }
                        waitUntil(timeout: testTimeout) { done in
                            realtime.connection.on(.connected) { _ in
                                expect(realtime.auth.clientId).to(equal("*"))
                                done()
                            }
                        }
                    }

                }
                
                // RSA7c
                it("should clientId be null or string") {
                    let clientOptions = AblyTests.setupOptions(AblyTests.jsonRestOptions)
                    clientOptions.clientId = "*"
                    
                    expect{ ARTRest(options: clientOptions) }.to(raiseException())
                }
            }
        }
        
        // RSA8
        describe("requestToken") {
            context("arguments") {
                // RSA8e
                it("should not merge with the configured params and options but instead replace all corresponding values, even when @null@") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "сlientId"
                    let rest = ARTRest(options: options)

                    let tokenParams = ARTTokenParams()
                    tokenParams.ttl = 2000
                    tokenParams.capability = "{\"cansubscribe:*\":[\"subscribe\"]}"

                    let precedenceOptions = AblyTests.commonAppSetup()

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken(tokenParams, with: precedenceOptions) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            expect(tokenDetails!.capability).to(equal("{\"cansubscribe:*\":[\"subscribe\"]}"))
                            expect(tokenDetails!.clientId).to(beNil())
                            expect(tokenDetails!.expires!.timeIntervalSince1970 - tokenDetails!.issued!.timeIntervalSince1970).to(equal(tokenParams.ttl as? Double))
                            done()
                        }
                    }

                    let options2 = AblyTests.commonAppSetup()
                    options2.clientId = nil
                    let rest2 = ARTRest(options: options2)

                    let precedenceOptions2 = AblyTests.commonAppSetup()
                    precedenceOptions2.clientId = nil

                    waitUntil(timeout: testTimeout) { done in
                        rest2.auth.requestToken(nil, with: precedenceOptions2) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                XCTFail("tokenDetails is nil"); done(); return
                            }
                            expect(tokenDetails.clientId).to(beNil())
                            done()
                        }
                    }
                }

                // RSA8e
                it("should use configured defaults if the object arguments are omitted") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "tester"
                    let rest = ARTRest(options: options)

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken(nil, with: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            expect(tokenDetails!.capability).to(equal("{\"*\":[\"*\"]}"))
                            expect(tokenDetails!.clientId).to(equal("tester"))
                            done()
                        }
                    }

                    let tokenParams = ARTTokenParams()
                    tokenParams.ttl = 2000
                    tokenParams.capability = "{\"cansubscribe:*\":[\"subscribe\"]}"
                    tokenParams.clientId = nil

                    let authOptions = ARTAuthOptions()
                    authOptions.key = options.key

                    // Provide TokenParams and Options
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken(tokenParams, with: authOptions) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            expect(tokenDetails!.capability).to(equal("{\"cansubscribe:*\":[\"subscribe\"]}"))
                            expect(tokenDetails!.clientId).to(beNil())
                            expect(tokenDetails!.expires!.timeIntervalSince1970 - tokenDetails!.issued!.timeIntervalSince1970).to(equal(tokenParams.ttl as? Double))
                            done()
                        }
                    }

                    // Provide TokenParams as null
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken(nil, with: authOptions) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            expect(tokenDetails!.capability).to(equal("{\"*\":[\"*\"]}"))
                            expect(tokenDetails!.clientId).to(equal("tester"))
                            expect(tokenDetails!.expires!.timeIntervalSince1970 - tokenDetails!.issued!.timeIntervalSince1970).to(equal(ARTDefault.ttl()))
                            done()
                        }
                    }

                    // Omit arguments
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            expect(tokenDetails!.capability).to(equal("{\"*\":[\"*\"]}"))
                            expect(tokenDetails!.clientId).to(equal("tester"))
                            done()
                        }
                    }
                }
            }

            // RSA8c
            context("authUrl") {

                it("query will provide a token string") {
                    let testToken = getTestToken()

                    let options = AblyTests.clientOptions()
                    options.authUrl = URL(string: "http://echo.ably.io")
                    expect(options.authUrl).toNot(beNil())
                    // Plain text
                    options.authParams = [URLQueryItem]()
                    options.authParams!.append(URLQueryItem(name: "type", value: "text"))
                    options.authParams!.append(URLQueryItem(name: "body", value: testToken))

                    let rest = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    rest.internal.httpExecutor = testHTTPExecutor

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken(nil, with: nil, callback: { tokenDetails, error in
                            expect(testHTTPExecutor.requests.last?.url?.host).to(equal("echo.ably.io"))
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            expect(tokenDetails?.token).to(equal(testToken))
                            done()
                        })
                    }
                }

                it("query will provide a TokenDetails") {
                    guard let testTokenDetails = getTestTokenDetails(clientId: "tester") else {
                        fail("TokenDetails is empty")
                        return
                    }

                    let encoder = ARTJsonLikeEncoder()
                    encoder.delegate = ARTJsonEncoder()
                    guard let jsonTokenDetails = try? encoder.encode(testTokenDetails) else {
                        fail("Invalid TokenDetails")
                        return
                    }

                    let options = ARTClientOptions()
                    options.authUrl = URL(string: "http://echo.ably.io")
                    expect(options.authUrl).toNot(beNil())
                    // JSON with TokenDetails
                    options.authParams = [URLQueryItem]()
                    options.authParams?.append(URLQueryItem(name: "type", value: "json"))
                    options.authParams?.append(URLQueryItem(name: "body", value: jsonTokenDetails.toUTF8String))

                    let rest = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    rest.internal.httpExecutor = testHTTPExecutor

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken(nil, with: nil, callback: { tokenDetails, error in
                            expect(testHTTPExecutor.requests.last?.url?.host).to(equal("echo.ably.io"))
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            expect(tokenDetails?.clientId) == testTokenDetails.clientId
                            expect(tokenDetails?.capability) == testTokenDetails.capability
                            expect(tokenDetails?.issued).toNot(beNil())
                            expect(tokenDetails?.expires).toNot(beNil())
                            if let issued = tokenDetails?.issued, let testIssued = testTokenDetails.issued {
                                expect(issued.compare(testIssued)) == ComparisonResult.orderedSame
                            }
                            if let expires = tokenDetails?.expires, let testExpires = testTokenDetails.expires {
                                expect(expires.compare(testExpires)) == ComparisonResult.orderedSame
                            }
                            done()
                        })
                    }
                }

                it("query will provide a TokenRequest") {
                    let tokenParams = ARTTokenParams()
                    tokenParams.capability = "{\"test\":[\"subscribe\"]}"

                    let options = AblyTests.commonAppSetup()
                    options.authUrl = URL(string: "http://echo.ably.io")
                    expect(options.authUrl).toNot(beNil())

                    var rest = ARTRest(options: options)

                    var tokenRequest: ARTTokenRequest?
                    waitUntil(timeout: testTimeout) { done in
                        // Sandbox and valid TokenRequest
                        rest.auth.createTokenRequest(tokenParams, options: nil, callback: { newTokenRequest, error in
                            expect(error).to(beNil())
                            tokenRequest = newTokenRequest
                            done()
                        })
                    }

                    guard let testTokenRequest = tokenRequest else {
                        fail("TokenRequest is empty")
                        return
                    }

                    let encoder = ARTJsonLikeEncoder()
                    encoder.delegate = ARTJsonEncoder()
                    guard let jsonTokenRequest = try? encoder.encode(testTokenRequest) else {
                        fail("Invalid TokenRequest")
                        return
                    }

                    // JSON with TokenRequest
                    options.authParams = [URLQueryItem]()
                    options.authParams?.append(URLQueryItem(name: "type", value: "json"))
                    options.authParams?.append(URLQueryItem(name: "body", value: jsonTokenRequest.toUTF8String))

                    rest = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    rest.internal.httpExecutor = testHTTPExecutor

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken(nil, with: nil, callback: { tokenDetails, error in
                            expect(testHTTPExecutor.requests.first?.url?.host).to(equal("echo.ably.io"))
                            expect(testHTTPExecutor.requests.last?.url?.host).toNot(equal("echo.ably.io"))
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is empty"); done()
                                return
                            }
                            expect(tokenDetails.token).toNot(beNil())
                            expect(tokenDetails.capability) == tokenParams.capability
                            done()
                        })
                    }
                }

                context("parameters") {
                    // RSA8c1a
                    it("should be added to the URL when auth method is GET") {
                        let clientOptions = ARTClientOptions()
                        clientOptions.authUrl = URL(string: "http://auth.ably.io")
                        var authParams = [
                            "param1": "value",
                            "param2": "value",
                            "clientId": "should not be overwritten",
                        ]
                        clientOptions.authParams = authParams.map {
                             URLQueryItem(name: $0, value: $1)
                        }
                        clientOptions.authHeaders = ["X-Header-1": "foo", "X-Header-2": "bar"]
                        let tokenParams = ARTTokenParams()
                        tokenParams.clientId = "test"

                        let rest = ARTRest(options: clientOptions)
                        let request = rest.auth.internal.buildRequest(clientOptions, with: tokenParams)

                        for (header, expectedValue) in clientOptions.authHeaders! {
                            if let value = request.allHTTPHeaderFields?[header] {
                                expect(value).to(equal(expectedValue))
                            } else {
                                fail("Missing header in request: \(header), expected: \(expectedValue)")
                            }
                        }
                        
                        guard let url = request.url else {
                            fail("Request is invalid")
                            return
                        }
                        guard let urlComponents = NSURLComponents(url: url, resolvingAgainstBaseURL: false) else {
                            fail("invalid URL: \(url)")
                            return
                        }
                        expect(urlComponents.scheme).to(equal("http"))
                        expect(urlComponents.host).to(equal("auth.ably.io"))
                        guard let queryItems = urlComponents.queryItems else {
                            fail("URL without query: \(url)")
                            return
                        }
                        for queryItem in queryItems {
                            if var expectedValue = authParams[queryItem.name] {
                                if queryItem.name == "clientId" {
                                    expectedValue = "test"
                                }
                                expect(queryItem.value!).to(equal(expectedValue))
                                authParams.removeValue(forKey: queryItem.name)
                            }
                        }
                        expect(authParams).to(beEmpty())
                    }
                    
                    // RSA8c1b
                    it("should added on the body request when auth method is POST") {
                        let clientOptions = ARTClientOptions()
                        clientOptions.authUrl = URL(string: "http://auth.ably.io")
                        clientOptions.authParams = [
                            URLQueryItem(name: "identifier", value: "123")
                        ]
                        clientOptions.authMethod = "POST"
                        clientOptions.authHeaders = ["X-Header-1": "foo", "X-Header-2": "bar"]
                        let tokenParams = ARTTokenParams()
                        tokenParams.ttl = 2000
                        tokenParams.capability = "{\"cansubscribe:*\":[\"subscribe\"]}"
                        
                        let rest = ARTRest(options: clientOptions)
                        
                        let request = rest.auth.internal.buildRequest(clientOptions, with: tokenParams)

                        guard let httpBodyData = request.httpBody else {
                            fail("Body is missing"); return
                        }
                        guard let httpBodyString = String(data: httpBodyData, encoding: .utf8) else {
                            fail("Body should be a string"); return
                        }

                        let expectedFormEncoding = "capability=%7B%22cansubscribe%3A%2A%22%3A%5B%22subscribe%22%5D%7D&identifier=123&ttl=2000"

                        expect(httpBodyString).to(equal(expectedFormEncoding))

                        expect(request.value(forHTTPHeaderField: "Content-Type")).to(equal("application/x-www-form-urlencoded"))

                        expect(request.value(forHTTPHeaderField: "Content-Length")).to(equal("89"))

                        for (header, expectedValue) in clientOptions.authHeaders! {
                            if let value = request.value(forHTTPHeaderField: header) {
                                expect(value).to(equal(expectedValue))
                            } else {
                                fail("Missing header in request: \(header), expected: \(expectedValue)")
                            }
                        }
                    }
                }

                // RSA8c2
                it("TokenParams should take precedence over any configured authParams when a name conflict occurs") {
                    let options = ARTClientOptions()
                    options.clientId = "john"
                    options.authUrl = URL(string: "http://auth.ably.io")
                    options.authMethod = "GET"
                    options.authHeaders = ["X-Header-1": "foo1", "X-Header-2": "foo2"]
                    let authParams = [
                        "key": "secret",
                        "clientId": "should be overridden"
                    ]
                    options.authParams = authParams.map { URLQueryItem(name: $0, value: $1) }

                    let tokenParams = ARTTokenParams()
                    tokenParams.clientId = "tester"

                    let client = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor

                    waitUntil(timeout: testTimeout) { done in
                        client.auth.requestToken(tokenParams, with: nil) { tokenDetails, error in
                            let query = testHTTPExecutor.requests[0].url!.query
                            expect(query).to(haveParam("clientId", withValue: tokenParams.clientId!))
                            done()
                        }
                    }
                }
                
                // RSA8c3
                it("should override previously configured parameters") {
                    let clientOptions = ARTClientOptions()
                    clientOptions.authUrl = URL(string: "http://auth.ably.io")
                    let rest = ARTRest(options: clientOptions)
                    
                    let authOptions = ARTAuthOptions()
                    authOptions.authUrl = URL(string: "http://auth.ably.io")
                    authOptions.authParams = [URLQueryItem(name: "ttl", value: "invalid")]
                    authOptions.authParams = [URLQueryItem(name: "test", value: "1")]
                    let url = rest.auth.internal.buildURL(authOptions, with: ARTTokenParams())
                    expect(url.absoluteString).to(contain(URL(string: "http://auth.ably.io")?.absoluteString ?? ""))
                }
            }

            // RSA8a
            it("implicitly creates a TokenRequest and requests a token") {
                let rest = ARTRest(options: AblyTests.commonAppSetup())

                var createTokenRequestMethodWasCalled = false

                // Adds a block of code after `createTokenRequest` is triggered
                let token = rest.auth.internal.testSuite_injectIntoMethod(after: NSSelectorFromString("_createTokenRequest:options:callback:")) {
                    createTokenRequestMethodWasCalled = true
                }
                defer { token.remove() }

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.requestToken(nil, with: nil, callback: { tokenDetails, error in
                        expect(error).to(beNil())
                        expect(tokenDetails?.token).toNot(beEmpty())
                        done()
                    })
                }

                expect(createTokenRequestMethodWasCalled).to(beTrue())
            }

            // RSA8b
            context("should support all TokenParams") {

                let currentClientId = "client_string"

                var options: ARTClientOptions!
                var rest: ARTRest!

                func setupDependencies() {
                    if (options == nil) {
                        options = AblyTests.commonAppSetup()
                        options.clientId = currentClientId
                        rest = ARTRest(options: options)
                    }
                }

                it("using defaults") {
                    setupDependencies()

                    // Default values
                    let defaultTokenParams = ARTTokenParams(clientId: currentClientId)
                    defaultTokenParams.ttl = ARTDefault.ttl() as NSNumber // Set by the server.

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken(nil, with: nil, callback: { tokenDetails, error in
                            expect(tokenDetails?.clientId).to(equal(defaultTokenParams.clientId))
                            expect(defaultTokenParams.capability).to(beNil())
                            expect(tokenDetails?.capability).to(equal("{\"*\":[\"*\"]}")) //Ably supplied capabilities of the underlying key
                            expect(tokenDetails?.issued).toNot(beNil())
                            expect(tokenDetails?.expires).toNot(beNil())
                            if let issued = tokenDetails?.issued, let expires = tokenDetails?.expires {
                                expect(expires.timeIntervalSince(issued)).to(equal(defaultTokenParams.ttl as? TimeInterval))
                            }
                            done()
                        })
                    }
                }

                it("overriding defaults") {
                    setupDependencies()

                    // Custom values
                    let expectedTtl = 4800.0
                    let expectedCapability = "{\"canpublish:*\":[\"publish\"]}"

                    let tokenParams = ARTTokenParams(clientId: currentClientId)
                    tokenParams.ttl = NSNumber(value: expectedTtl)
                    tokenParams.capability = expectedCapability

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken(tokenParams, with: nil, callback: { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails?.clientId).to(equal(options.clientId))
                            expect(tokenDetails?.capability).to(equal(expectedCapability))
                            expect(tokenDetails?.issued).toNot(beNil())
                            expect(tokenDetails?.expires).toNot(beNil())
                            if let issued = tokenDetails?.issued, let expires = tokenDetails?.expires {
                                expect(expires.timeIntervalSince(issued)).to(equal(expectedTtl))
                            }
                            done()
                        })
                    }
                }
            }

            // RSA8d
            context("When authCallback option is set, it will invoke the callback") {

                it("with a token string") {
                    let options = AblyTests.clientOptions()
                    let expectedTokenParams = ARTTokenParams()

                    options.authCallback = { tokenParams, completion in
                        expect(tokenParams.clientId).to(beNil())
                        completion("token_string" as ARTTokenDetailsCompatible?, nil)
                    }
                    let rest = ARTRest(options: options)

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken(expectedTokenParams, with: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails!.token).to(equal("token_string"))
                            done()
                        }
                    }
                }

                it("with a TokenDetails") {
                    let expectedTokenParams = ARTTokenParams()

                    let options = AblyTests.clientOptions()
                    options.authCallback = { tokenParams, completion in
                        expect(tokenParams.clientId).to(beNil())
                        completion(ARTTokenDetails(token: "token_from_details"), nil)
                    }
                    let rest = ARTRest(options: options)

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken(expectedTokenParams, with: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails!.token).to(equal("token_from_details"))
                            done()
                        }
                    }
                }

                it("with a TokenRequest") {
                    let options = AblyTests.commonAppSetup()
                    let expectedTokenParams = ARTTokenParams()
                    expectedTokenParams.clientId = "foo"
                    var rest: ARTRest!

                    options.authCallback = { tokenParams, completion in
                        expect(tokenParams.clientId).to(beIdenticalTo(expectedTokenParams.clientId))
                        rest.auth.createTokenRequest(tokenParams, options: options) { tokenRequest, error in
                            completion(tokenRequest, error)
                        }
                    }

                    rest = ARTRest(options: options)

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken(expectedTokenParams, with: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("tokenDetails is nil"); done(); return
                            }
                            expect(tokenDetails.clientId).to(equal(expectedTokenParams.clientId))
                            done()
                        }
                    }
                }
            }

            // RSA8f1
            it("ensure the message published does not have a clientId") {
                let options = AblyTests.commonAppSetup()
                options.token = getTestToken(clientId: nil)
                let rest = ARTRest(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                rest.internal.httpExecutor = testHTTPExecutor
                let channel = rest.channels.get("test")

                waitUntil(timeout: testTimeout) { done in
                    let message = ARTMessage(name: nil, data: "message without an explicit clientId")
                    expect(message.clientId).to(beNil())
                    channel.publish([message]) { error in
                        expect(error).to(beNil())
                        switch extractBodyAsMessages(testHTTPExecutor.requests.first) {
                        case .failure(let error):
                            fail(error)
                        case .success(let httpBody):
                            expect(httpBody.unbox.first!["clientId"]).to(beNil())
                        }
                        channel.history { page, error in
                            expect(error).to(beNil())
                            guard let page = page else {
                                fail("Result is empty"); done(); return
                            }
                            expect(page.items).to(haveCount(1))
                            expect((page.items[0] ).clientId).to(beNil())
                            done()
                        }
                    }
                }
                expect(rest.auth.clientId).to(beNil())
            }

            // RSA8f2
            it("ensure that the message is rejected") {
                let options = AblyTests.commonAppSetup()
                options.token = getTestToken(clientId: nil)
                let rest = ARTRest(options: options)
                let channel = rest.channels.get("test")

                waitUntil(timeout: testTimeout) { done in
                    let message = ARTMessage(name: nil, data: "message with an explicit clientId", clientId: "john")
                    channel.publish([message]) { error in
                        guard let error = error else {
                            fail("Error is nil"); done(); return
                        }
                        expect(error.message).to(contain("mismatched clientId"))
                        done()
                    }
                }
                expect(rest.auth.clientId).to(beNil())
            }

            // RSA8f3
            it("ensure the message published with a wildcard '*' does not have a clientId") {
                let options = AblyTests.commonAppSetup()
                let rest = ARTRest(options: options)

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.authorize(ARTTokenParams(clientId: "*"), options: nil) { _, error in
                        expect(error).to(beNil())
                        done()
                    }
                }

                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                rest.internal.httpExecutor = testHTTPExecutor
                let channel = rest.channels.get("test")

                waitUntil(timeout: testTimeout) { done in
                    let message = ARTMessage(name: nil, data: "no client")
                    expect(message.clientId).to(beNil())
                    channel.publish([message]) { error in
                        expect(error).to(beNil())
                        switch extractBodyAsMessages(testHTTPExecutor.requests.first) {
                        case .failure(let error):
                            fail(error)
                        case .success(let httpBody):
                            expect(httpBody.unbox.first!["clientId"]).to(beNil())
                        }
                        channel.history { page, error in
                            guard let page = page else {
                                fail("Page is empty"); done(); return
                            }
                            expect(error).to(beNil())
                            expect(page.items).to(haveCount(1))
                            expect(page.items[0].clientId).to(beNil())
                            done()
                        }
                    }
                }
                expect(rest.auth.clientId).to(equal("*"))
            }

            // RSA8f4
            it("ensure the message published with a wildcard '*' has the provided clientId") {
                let options = AblyTests.commonAppSetup()
                // Request a token with a wildcard '*' value clientId
                options.token = getTestToken(clientId: "*")
                let rest = ARTRest(options: options)
                let channel = rest.channels.get("test")

                waitUntil(timeout: testTimeout) { done in
                    let message = ARTMessage(name: nil, data: "message with an explicit clientId", clientId: "john")
                    channel.publish([message]) { error in
                        expect(error).to(beNil())
                        channel.history { page, error in
                            expect(error).to(beNil())
                            guard let page = page else {
                                fail("Page is empty"); done(); return
                            }
                            guard let item = page.items.first else {
                                fail("First item does not exist"); done(); return
                            }
                            expect(item.clientId).to(equal("john"))
                            done()
                        }
                    }
                }
                expect(rest.auth.clientId).to(beNil())
            }
        }

        // RSA9
        describe("createTokenRequest") {

            // RSA9h
            it("should not merge with the configured params and options but instead replace all corresponding values, even when @null@") {
                let options = AblyTests.commonAppSetup()
                options.clientId = "client_string"
                let rest = ARTRest(options: options)

                let tokenParams = ARTTokenParams()
                let defaultCapability = tokenParams.capability
                expect(defaultCapability).to(beNil())

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.createTokenRequest(nil, options: nil) { tokenRequest, error in
                        expect(error).to(beNil())
                        guard let tokenRequest = tokenRequest else {
                            XCTFail("tokenRequest is nil"); done(); return
                        }
                        expect(tokenRequest.clientId).to(equal(options.clientId))
                        expect(tokenRequest.ttl).to(beNil())
                        expect(tokenRequest.capability).to(beNil())
                        done()
                    }
                }

                tokenParams.ttl = NSNumber(value: ExpectedTokenParams.ttl)
                tokenParams.capability = ExpectedTokenParams.capability
                tokenParams.clientId = nil

                let authOptions = ARTAuthOptions()
                authOptions.queryTime = true
                authOptions.key = options.key

                let mockServerDate = Date().addingTimeInterval(120)
                rest.auth.internal.testSuite_returnValue(for: NSSelectorFromString("handleServerTime:"), with: mockServerDate)

                var serverTimeRequestCount = 0
                let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(_:))) {
                    serverTimeRequestCount += 1
                }
                defer { hook.remove() }

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.createTokenRequest(tokenParams, options: authOptions) { tokenRequest, error in
                        expect(error).to(beNil())
                        guard let tokenRequest = tokenRequest else {
                            XCTFail("tokenRequest is nil"); done(); return
                        }
                        expect(tokenRequest.clientId).to(beNil())
                        expect(tokenRequest.timestamp).to(beCloseTo(mockServerDate))
                        expect(serverTimeRequestCount) == 1
                        expect(tokenRequest.ttl).to(equal(ExpectedTokenParams.ttl as NSNumber))
                        expect(tokenRequest.capability).to(equal(ExpectedTokenParams.capability))
                        done()
                    }
                }

                tokenParams.clientId = "newClientId"
                tokenParams.ttl = 2000
                tokenParams.capability = "{ \"test:*\":[\"test\"] }"

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.createTokenRequest(tokenParams, options: authOptions) { tokenRequest, error in
                        expect(error).to(beNil())
                        guard let tokenRequest = tokenRequest else {
                            XCTFail("tokenRequest is nil"); done(); return
                        }
                        expect(tokenRequest.clientId).to(equal("newClientId"))
                        expect(tokenRequest.ttl).to(equal(2000))
                        expect(tokenRequest.capability).to(equal("{ \"test:*\":[\"test\"] }"))
                        done()
                    }
                }

                tokenParams.clientId = nil

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.createTokenRequest(tokenParams, options: authOptions) { tokenRequest, error in
                        expect(error).to(beNil())
                        guard let tokenRequest = tokenRequest else {
                            XCTFail("tokenRequest is nil"); done(); return
                        }
                        expect(tokenRequest.clientId).to(beNil())
                        done()
                    }
                }
            }

            it("should override defaults if AuthOptions provided") {
                let defaultOptions = AblyTests.commonAppSetup()
                defaultOptions.authCallback = { tokenParams, completion in
                    fail("Should not be called")
                }

                var testTokenRequest: ARTTokenRequest?
                let rest = ARTRest(options: defaultOptions)
                rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, error in
                    testTokenRequest = tokenRequest
                })
                expect(testTokenRequest).toEventuallyNot(beNil(), timeout: testTimeout)

                var customCallbackCalled = false
                let customOptions = ARTAuthOptions()
                customOptions.authCallback = { tokenParams, completion in
                    customCallbackCalled = true
                    completion(testTokenRequest, nil)
                }

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.authorize(nil, options: customOptions) { _, error in
                        expect(error).to(beNil())
                        done()
                    }
                }
                expect(customCallbackCalled).to(beTrue())
            }

            it("should use defaults if no AuthOptions is provided") {
                var currentTokenRequest: ARTTokenRequest? = nil
                var callbackCalled = false

                let defaultOptions = AblyTests.commonAppSetup()
                defaultOptions.authCallback = { tokenParams, completion in
                    callbackCalled = true
                    guard let tokenRequest = currentTokenRequest else {
                        fail("tokenRequest is nil"); return
                    }
                    completion(tokenRequest, nil)
                }

                let rest = ARTRest(options: defaultOptions)
                rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, error in
                    currentTokenRequest = tokenRequest
                })
                expect(currentTokenRequest).toEventuallyNot(beNil(), timeout: testTimeout)

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.authorize(nil, options: nil) { _, error in
                        expect(error).to(beNil())
                        done()
                    }
                }
                expect(callbackCalled).to(beTrue())
            }

            it("should replace defaults if `nil` option's field passed") {
                let defaultOptions = AblyTests.commonAppSetup()
                let rest = ARTRest(options: defaultOptions)

                let customOptions = ARTAuthOptions()

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.createTokenRequest(nil, options: customOptions) { tokenRequest, error in
                        guard let error = error else {
                            fail("Error is nil"); done(); return
                        }
                        expect(error.localizedDescription).to(contain("no key provided for signing token requests"))
                        done()
                    }
                }
            }

            // RSA9h
            it("should use configured defaults if the object arguments are omitted") {
                let options = AblyTests.commonAppSetup()
                let rest = ARTRest(options: options)

                let tokenParams = ARTTokenParams()
                tokenParams.clientId = "tester"
                tokenParams.ttl = 2000
                tokenParams.capability = "{\"foo:*\":[\"publish\"]}"

                let authOptions = ARTAuthOptions()
                authOptions.queryTime = true
                authOptions.key = options.key

                var serverTimeRequestCount = 0
                let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(_:))) {
                    serverTimeRequestCount += 1
                }
                defer { hook.remove() }

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.createTokenRequest(tokenParams, options: authOptions) { tokenRequest, error in
                        expect(error).to(beNil())
                        guard let tokenRequest = tokenRequest else {
                            XCTFail("TokenRequest is nil"); done(); return
                        }
                        expect(tokenRequest.clientId) == tokenParams.clientId
                        expect(tokenRequest.ttl) == tokenParams.ttl
                        expect(tokenRequest.capability) == tokenParams.capability
                        done()
                    }
                }

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.createTokenRequest { tokenRequest, error in
                        expect(error).to(beNil())
                        guard let tokenRequest = tokenRequest else {
                            XCTFail("TokenRequest is nil"); done(); return
                        }
                        expect(tokenRequest.clientId).to(beNil())
                        expect(tokenRequest.ttl).to(beNil())
                        expect(tokenRequest.capability).to(beNil())
                        done()
                    }
                }

                expect(serverTimeRequestCount) == 1
            }

            // RSA9a
            it("should create and sign a TokenRequest") {
                let rest = ARTRest(options: AblyTests.commonAppSetup())
                let expectedClientId = "client_string"
                let tokenParams = ARTTokenParams(clientId: expectedClientId)

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.createTokenRequest(tokenParams, options: nil, callback: { tokenRequest, error in
                        defer { done() }
                        expect(error).to(beNil())
                        guard let tokenRequest = tokenRequest else {
                            XCTFail("TokenRequest is nil"); return
                        }
                        expect(tokenRequest).to(beAnInstanceOf(ARTTokenRequest.self))
                        expect(tokenRequest.clientId).to(equal(expectedClientId))
                        expect(tokenRequest.mac).toNot(beNil())
                        expect(tokenRequest.nonce).toNot(beNil())
                    })
                }
            }

            // RSA9b
            it("should support AuthOptions") {
                let rest = ARTRest(options: AblyTests.commonAppSetup())
                let auth: ARTAuth = rest.auth

                let authOptions = ARTAuthOptions(key: "key:secret")

                waitUntil(timeout: testTimeout) { done in
                    auth.createTokenRequest(nil, options: authOptions, callback: { tokenRequest, error in
                        defer { done() }
                        expect(error).to(beNil())
                        guard let tokenRequest = tokenRequest else {
                            XCTFail("TokenRequest is nil"); return
                        }
                        expect(tokenRequest.keyName).to(equal("key"))
                    })
                }
            }

            // RSA9c
            it("should generate a unique 16+ character nonce if none is provided") {
                let rest = ARTRest(options: AblyTests.commonAppSetup())

                waitUntil(timeout: testTimeout) { done in
                    // First
                    rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, error in
                        expect(error).to(beNil())
                        guard let tokenRequest1 = tokenRequest else {
                            XCTFail("TokenRequest1 is nil"); done(); return
                        }
                        expect(tokenRequest1.nonce).to(haveCount(16))

                        // Second
                        rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, error in
                            expect(error).to(beNil())
                            guard let tokenRequest2 = tokenRequest else {
                                XCTFail("TokenRequest2 is nil"); done(); return
                            }
                            expect(tokenRequest2.nonce).to(haveCount(16))

                            // Uniqueness
                            expect(tokenRequest1.nonce).toNot(equal(tokenRequest2.nonce))
                            done()
                        })
                    })
                }
            }

            // RSA9d
            context("should generate a timestamp") {

                it("from current time if not provided") {
                    let rest = ARTRest(options: AblyTests.commonAppSetup())

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, error in
                            defer { done() }
                            expect(error).to(beNil())
                            guard let tokenRequest = tokenRequest else {
                                XCTFail("TokenRequest is nil"); return
                            }
                            expect(tokenRequest.timestamp).to(beCloseTo(Date(), within: 1.0))
                        })
                    }
                }

                it("will retrieve the server time if queryTime is true") {
                    let rest = ARTRest(options: AblyTests.commonAppSetup())

                    var serverTimeRequestWasMade = false
                    let block: @convention(block) (AspectInfo) -> Void = { _ in
                        serverTimeRequestWasMade = true
                    }

                    let hook = ARTRestInternal.aspect_hook(rest.internal)
                    // Adds a block of code after `time` is triggered
                    let _ = try? hook(#selector(ARTRestInternal._time(_:)), .positionBefore, unsafeBitCast(block, to: ARTRestInternal.self))

                    let authOptions = ARTAuthOptions()
                    authOptions.queryTime = true
                    authOptions.key = AblyTests.commonAppSetup().key

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.createTokenRequest(nil, options: authOptions, callback: { tokenRequest, error in
                            expect(error).to(beNil())
                            guard let tokenRequest = tokenRequest else {
                                XCTFail("tokenRequest is nil"); done(); return
                            }
                            expect(tokenRequest.timestamp).toNot(beNil())
                            expect(serverTimeRequestWasMade).to(beTrue())
                            done()
                        })
                    }
                }
            }

            // RSA9e
            context("TTL") {

                it("should be optional") {
                    let rest = ARTRest(options: AblyTests.commonAppSetup())

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, error in
                            defer { done() }
                            expect(error).to(beNil())
                            guard let tokenRequest = tokenRequest else {
                                XCTFail("TokenRequest is nil"); return
                            }
                            //In Seconds because TTL property is a NSTimeInterval but further it does the conversion to milliseconds
                            expect(tokenRequest.ttl).to(beNil())
                        })
                    }

                    let tokenParams = ARTTokenParams()
                    expect(tokenParams.ttl).to(beNil())

                    let expectedTtl = TimeInterval(10)
                    tokenParams.ttl = NSNumber(value: expectedTtl)

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.createTokenRequest(tokenParams, options: nil, callback: { tokenRequest, error in
                            defer { done() }
                            expect(error).to(beNil())
                            guard let tokenRequest = tokenRequest else {
                                XCTFail("TokenRequest is nil"); return
                            }
                            expect(tokenRequest.ttl as? TimeInterval).to(equal(expectedTtl))
                        })
                    }
                }

                it("should be specified in milliseconds") {
                    let rest = ARTRest(options: AblyTests.commonAppSetup())

                    let params = ARTTokenParams()
                    params.ttl = NSNumber(value: 42)
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.createTokenRequest(params, options: nil, callback: { tokenRequest, error in
                            defer { done() }
                            expect(error).to(beNil())
                            guard let tokenRequest = tokenRequest else {
                                XCTFail("TokenRequest is nil"); return
                            }
                            expect(tokenRequest.ttl as? TimeInterval).to(equal(42))

                            // Check if the encoder changes the TTL to milliseconds
                            let encoder = rest.internal.defaultEncoder as! ARTJsonLikeEncoder
                            let data = try! encoder.encode(tokenRequest)
                            let jsonObject = (try! encoder.delegate!.decode(data)) as! NSDictionary
                            let ttl = jsonObject["ttl"] as! NSNumber
                            expect(ttl as? Int64).to(equal(42 * 1000))
                            
                            // Make sure it comes back the same.
                            let decoded = try! encoder.decodeTokenRequest(data)
                            expect(decoded.ttl as? TimeInterval).to(equal(42))
                        })
                    }
                }

                it("should be valid to request a token for 24 hours") {
                    let rest = ARTRest(options: AblyTests.commonAppSetup())
                    let tokenParams = ARTTokenParams()
                    let dayInSeconds = TimeInterval(24 * 60 * 60)
                    tokenParams.ttl = dayInSeconds as NSNumber

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.requestToken(tokenParams, with: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                XCTFail("TokenDetails is nil"); done(); return
                            }
                            expect(tokenDetails.expires!.timeIntervalSince(tokenDetails.issued!)).to(beCloseTo(dayInSeconds))
                            done()
                        }
                    }
                }

            }

            // RSA9f
            it("should provide capability has json text") {
                let rest = ARTRest(options: AblyTests.commonAppSetup())

                let tokenParams = ARTTokenParams()
                tokenParams.capability = "{ - }"

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.createTokenRequest(tokenParams, options: nil, callback: { tokenRequest, error in
                        defer { done() }
                        guard let error = error else {
                            XCTFail("Error is nil"); return
                        }
                        expect(error.localizedDescription).to(contain("Capability"))
                        expect(tokenRequest?.capability).to(beNil())
                    })
                }

                let expectedCapability = "{ \"cansubscribe:*\":[\"subscribe\"] }"
                tokenParams.capability = expectedCapability

                rest.auth.createTokenRequest(tokenParams, options: nil, callback: { tokenRequest, error in
                    expect(error).to(beNil())
                    guard let tokenRequest = tokenRequest else {
                        XCTFail("TokenRequest is nil"); return
                    }
                    expect(tokenRequest.capability).to(equal(expectedCapability))
                })
            }

            // RSA9g
            it("should generate a valid HMAC") {
                let rest = ARTRest(options: AblyTests.commonAppSetup())

                let tokenParams = ARTTokenParams(clientId: "client_string")

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.createTokenRequest(tokenParams, options: nil, callback: { tokenRequest, error in
                        expect(error).to(beNil())
                        guard let tokenRequest1 = tokenRequest else {
                            XCTFail("TokenRequest is nil"); done(); return
                        }
                        let signed = tokenParams.sign(rest.internal.options.key!, withNonce: tokenRequest1.nonce)
                        expect(tokenRequest1.mac).to(equal(signed?.mac))

                        rest.auth.createTokenRequest(tokenParams, options: nil, callback: { tokenRequest, error in
                            expect(error).to(beNil())
                            guard let tokenRequest2 = tokenRequest else {
                                XCTFail("TokenRequest is nil"); done(); return
                            }
                            expect(tokenRequest2.nonce).toNot(equal(tokenRequest1.nonce))
                            expect(tokenRequest2.mac).toNot(equal(tokenRequest1.mac))
                            done()
                        })
                    })
                }
            }

            // RSA9i
            it("should respect all requirements") {
                let rest = ARTRest(options: AblyTests.commonAppSetup())
                let expectedClientId = "client_string"
                let tokenParams = ARTTokenParams(clientId: expectedClientId)
                let expectedTtl = 6.0
                tokenParams.ttl = NSNumber(value: expectedTtl)
                let expectedCapability = "{}"
                tokenParams.capability = expectedCapability

                let authOptions = ARTAuthOptions()
                authOptions.queryTime = true
                authOptions.key = AblyTests.commonAppSetup().key

                var serverTime: Date?
                waitUntil(timeout: testTimeout) { done in
                    rest.time({ date, error in
                        serverTime = date
                        done()
                    })
                }
                expect(serverTime).toNot(beNil(), description: "Server time is nil")

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.createTokenRequest(tokenParams, options: authOptions, callback: { tokenRequest, error in
                        defer { done() }
                        expect(error).to(beNil())
                        guard let tokenRequest = tokenRequest else {
                            XCTFail("TokenRequest is nil"); return
                        }
                        expect(tokenRequest.clientId).to(equal(expectedClientId))
                        expect(tokenRequest.mac).toNot(beNil())
                        expect(tokenRequest.nonce).to(haveCount(16))
                        expect(tokenRequest.ttl as? TimeInterval).to(equal(expectedTtl))
                        expect(tokenRequest.capability).to(equal(expectedCapability))
                        expect(tokenRequest.timestamp).to(beCloseTo(serverTime!, within: 6.0))
                    })
                }
            }

        }

        // RSA10
        describe("authorize") {

            // RSA10a
            it("should always create a token") {
                let options = AblyTests.commonAppSetup()
                options.useTokenAuth = true
                let rest = ARTRest(options: options)
                let channel = rest.channels.get("test")

                waitUntil(timeout: testTimeout) { done in
                    channel.publish(nil, data: "first check") { error in
                        expect(error).to(beNil())
                        done()
                    }
                }

                // Check that token exists
                expect(rest.auth.internal.method).to(equal(ARTAuthMethod.token))
                guard let firstTokenDetails = rest.auth.tokenDetails else {
                    fail("TokenDetails is nil"); return
                }
                expect(firstTokenDetails.token).toNot(beNil())

                waitUntil(timeout: testTimeout) { done in
                    channel.publish(nil, data: "second check") { error in
                        expect(error).to(beNil())
                        done()
                    }
                }

                // Check that token has not changed
                expect(rest.auth.internal.method).to(equal(ARTAuthMethod.token))
                guard let secondTokenDetails = rest.auth.tokenDetails else {
                    fail("TokenDetails is nil"); return
                }
                expect(firstTokenDetails).to(beIdenticalTo(secondTokenDetails))

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.authorize(nil, options: nil, callback: { tokenDetails, error in
                        expect(error).to(beNil())
                        guard let tokenDetails = tokenDetails else {
                            XCTFail("TokenDetails is nil"); done(); return
                        }
                        // Check that token has changed
                        expect(tokenDetails.token).toNot(equal(firstTokenDetails.token))

                        channel.publish(nil, data: "third check") { error in
                            expect(error).to(beNil())
                            guard let thirdTokenDetails = rest.auth.tokenDetails else {
                                fail("TokenDetails is nil"); return
                            }
                            expect(thirdTokenDetails.token).to(equal(tokenDetails.token))
                            done()
                        }
                    })
                }
            }

            // RSA10a
            it("should create a new token if one already exist and ensure Token Auth is used for all future requests") {
                let options = AblyTests.commonAppSetup()
                let testToken = getTestToken()
                options.token = testToken
                let rest = ARTRest(options: options)

                expect(rest.auth.tokenDetails?.token).toNot(beNil())
                waitUntil(timeout: testTimeout) { done in
                    rest.auth.authorize(nil, options: nil, callback: { tokenDetails, error in
                        guard let tokenDetails = tokenDetails else {
                            XCTFail("TokenDetails is nil"); done(); return
                        }
                        expect(tokenDetails.token).toNot(equal(testToken))
                        expect(rest.auth.internal.method).to(equal(ARTAuthMethod.token))

                        publishTestMessage(rest, completion: { error in
                            expect(error).to(beNil())
                            expect(rest.auth.internal.method).to(equal(ARTAuthMethod.token))
                            expect(rest.auth.tokenDetails?.token).to(equal(tokenDetails.token))
                            done()
                        })
                    })
                }
            }

            // RSA10a
            it("should create a token immediately and ensures Token Auth is used for all future requests") {
                let options = AblyTests.commonAppSetup()
                let rest = ARTRest(options: options)

                expect(rest.auth.tokenDetails?.token).to(beNil())
                waitUntil(timeout: testTimeout) { done in
                    rest.auth.authorize(nil, options: nil, callback: { tokenDetails, error in
                        guard let tokenDetails = tokenDetails else {
                            XCTFail("TokenDetails is nil"); done(); return
                        }
                        expect(tokenDetails.token).toNot(beNil())
                        expect(rest.auth.internal.method).to(equal(ARTAuthMethod.token))

                        publishTestMessage(rest, completion: { error in
                            expect(error).to(beNil())
                            expect(rest.auth.internal.method).to(equal(ARTAuthMethod.token))
                            expect(rest.auth.tokenDetails?.token).to(equal(tokenDetails.token))
                            done()
                        })
                    })
                }
            }

            // RSA10b
            it("should supports all TokenParams and AuthOptions") {
                let rest = ARTRest(options: AblyTests.commonAppSetup())

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.authorize(ARTTokenParams(), options: ARTAuthOptions(), callback: { tokenDetails, error in
                        guard let error = error as? ARTErrorInfo else {
                            fail("Error is nil"); done(); return
                        }
                        expect(error.localizedDescription).to(contain("no means to renew the token is provided"))
                        done()
                    })
                }
            }

            // RSA10e
            it("should use the requestToken implementation") {
                let rest = ARTRest(options: AblyTests.commonAppSetup())

                var requestMethodWasCalled = false
                let block: @convention(block) (AspectInfo) -> Void = { _ in
                    requestMethodWasCalled = true
                }

                let hook = ARTAuthInternal.aspect_hook(rest.auth.internal)
                // Adds a block of code after `requestToken` is triggered
                let token = try? hook(#selector(ARTAuthInternal._requestToken(_:with:callback:)), [], unsafeBitCast(block, to: ARTAuthInternal.self))

                expect(token).toNot(beNil())

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.authorize(nil, options: nil, callback: { tokenDetails, error in
                        expect(error).to(beNil())
                        guard let tokenDetails = tokenDetails else {
                            XCTFail("TokenDetails is nil"); done(); return
                        }
                        expect(tokenDetails.token).toNot(beEmpty())
                        done()
                    })
                }

                expect(requestMethodWasCalled).to(beTrue())
            }

            // RSA10f
            it("should return TokenDetails with valid token metadata") {
                let options = AblyTests.commonAppSetup()
                options.clientId = "client_string"
                let rest = ARTRest(options: options)

                waitUntil(timeout: testTimeout) { done in
                    rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                        expect(error).to(beNil())
                        guard let tokenDetails = tokenDetails else {
                            XCTFail("TokenDetails is nil"); done(); return
                        }
                        expect(tokenDetails).to(beAnInstanceOf(ARTTokenDetails.self))
                        expect(tokenDetails.token).toNot(beEmpty())
                        expect(tokenDetails.expires!.timeIntervalSinceNow).to(beGreaterThan(tokenDetails.issued!.timeIntervalSinceNow))
                        expect(tokenDetails.clientId).to(equal(options.clientId))
                        done()
                    }
                }
            }

            // RSA10g
            context("on subsequent authorisations") {

                it("should store the AuthOptions with authUrl") {
                    let options = AblyTests.commonAppSetup()
                    let rest = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    rest.internal.httpExecutor = testHTTPExecutor
                    let auth = rest.auth

                    let token = getTestToken()
                    let authOptions = ARTAuthOptions()
                    // Use authUrl for authentication with plain text token response
                    authOptions.authUrl = URL(string: "http://echo.ably.io")!
                    authOptions.authParams = [URLQueryItem]()
                    authOptions.authParams?.append(URLQueryItem(name: "type", value: "text"))
                    authOptions.authParams?.append(URLQueryItem(name: "body", value: token))
                    authOptions.authHeaders = ["X-Ably":"Test"]
                    authOptions.queryTime = true

                    waitUntil(timeout: testTimeout) { done in
                        auth.authorize(nil, options: authOptions) { tokenDetails, error in
                            expect(error).to(beNil())

                            guard let tokenDetails = tokenDetails else {
                                XCTFail("TokenDetails is nil"); done(); return
                            }
                            expect(tokenDetails.token).to(equal(token))
                            
                            auth.authorize(nil, options: nil) { tokenDetails, error in
                                expect(error).to(beNil())

                                guard let tokenDetails = tokenDetails else {
                                    XCTFail("TokenDetails is nil"); done(); return
                                }
                                expect(testHTTPExecutor.requests.last?.url?.host).to(equal("echo.ably.io"))
                                expect(auth.internal.options.authUrl!.host).to(equal("echo.ably.io"))
                                expect(auth.internal.options.authHeaders!["X-Ably"]).to(equal("Test"))
                                expect(tokenDetails.token).to(equal(token))
                                expect(auth.internal.options.queryTime).to(beFalse())
                                done()
                            }
                        }
                    }
                }

                it("should store the AuthOptions with authCallback") {
                    let rest = ARTRest(options: AblyTests.commonAppSetup())
                    let auth = rest.auth

                    var authCallbackHasBeenInvoked = false

                    let authOptions = ARTAuthOptions()
                    authOptions.authCallback = { tokenParams, completion in
                        authCallbackHasBeenInvoked = true
                        completion(ARTTokenDetails(token: "token"), nil)
                    }
                    authOptions.useTokenAuth = true
                    authOptions.queryTime = true

                    waitUntil(timeout: testTimeout) { done in
                        auth.authorize(nil, options: authOptions) { tokenDetails, error in
                            expect(authCallbackHasBeenInvoked).to(beTrue())

                            authCallbackHasBeenInvoked = false
                            let authOptions2 = ARTAuthOptions()

                            auth.internal.testSuite_forceTokenToExpire()

                            auth.authorize(nil, options: authOptions2) { tokenDetails, error in
                                expect(authCallbackHasBeenInvoked).to(beFalse())
                                expect(auth.internal.options.useTokenAuth).to(beFalse())
                                expect(auth.internal.options.queryTime).to(beFalse())
                                done()
                            }
                        }
                    }
                }

                it("should not store queryTime") {
                    let options = AblyTests.commonAppSetup()
                    let rest = ARTRest(options: options)
                    let authOptions = ARTAuthOptions()
                    authOptions.key = options.key
                    authOptions.queryTime = true

                    var serverTimeRequestWasMade = false
                    let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(_:))) {
                        serverTimeRequestWasMade = true
                    }
                    defer { hook.remove() }

                    waitUntil(timeout: testTimeout) { done in
                        // First time
                        rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            expect(serverTimeRequestWasMade).to(beTrue())
                            expect(rest.auth.internal.options.queryTime).to(beFalse())
                            serverTimeRequestWasMade = false

                            // Second time
                            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                                expect(error).to(beNil())
                                expect(tokenDetails).toNot(beNil())
                                expect(serverTimeRequestWasMade).to(beFalse())
                                expect(rest.auth.internal.options.queryTime).to(beFalse())
                                done()
                            }
                        }
                    }
                }

                it("should store the TokenParams") {
                    let rest = ARTRest(options: AblyTests.commonAppSetup())

                    let tokenParams = ARTTokenParams()
                    tokenParams.clientId = ExpectedTokenParams.clientId
                    tokenParams.ttl = ExpectedTokenParams.ttl as NSNumber
                    tokenParams.capability = ExpectedTokenParams.capability

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(tokenParams, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        delay(tokenParams.ttl as! TimeInterval + 1.0) {
                            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                                expect(error).to(beNil())
                                guard let tokenDetails = tokenDetails else {
                                    XCTFail("TokenDetails is nil"); done(); return
                                }
                                expect(tokenDetails.clientId).to(equal(ExpectedTokenParams.clientId))
                                expect(tokenDetails.issued!.addingTimeInterval(ExpectedTokenParams.ttl)).to(beCloseTo(tokenDetails.expires!))
                                expect(tokenDetails.capability).to(equal(ExpectedTokenParams.capability))
                                done()
                            }
                        }
                    }
                }

                it("should use configured defaults if the object arguments are omitted") {
                    let options = AblyTests.commonAppSetup()
                    let rest = ARTRest(options: options)

                    let tokenParams = ARTTokenParams()
                    tokenParams.clientId = ExpectedTokenParams.clientId
                    tokenParams.ttl = ExpectedTokenParams.ttl as NSNumber
                    tokenParams.capability = ExpectedTokenParams.capability

                    let authOptions = ARTAuthOptions()
                    var authCallbackCalled = 0
                    authOptions.authCallback = { tokenParams, completion in
                        expect(tokenParams.clientId) == ExpectedTokenParams.clientId
                        expect(tokenParams.ttl as? TimeInterval) == ExpectedTokenParams.ttl
                        expect(tokenParams.capability) == ExpectedTokenParams.capability
                        authCallbackCalled += 1
                        getTestTokenDetails(key: options.key, completion: completion)
                    }

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(tokenParams, options: authOptions) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            done()
                        }
                    }

                    expect(authCallbackCalled) == 2
                }

            }

            // RSA10h
            it("should use the configured Auth#clientId, if not null, by default") {
                let options = AblyTests.commonAppSetup()
                var rest = ARTRest(options: options)

                // ClientId null
                waitUntil(timeout: testTimeout) { done in
                    rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                        expect(error).to(beNil())
                        guard let tokenDetails = tokenDetails else {
                            XCTFail("TokenDetails is nil"); done(); return
                        }
                        expect(tokenDetails.clientId).to(beNil())
                        done()
                    }
                }

                options.clientId = "client_string"
                rest = ARTRest(options: options)

                // ClientId not null
                waitUntil(timeout: testTimeout) { done in
                    rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                        expect(error).to(beNil())
                        guard let tokenDetails = tokenDetails else {
                            XCTFail("TokenDetails is nil"); done(); return
                        }
                        expect(tokenDetails.clientId).to(equal(options.clientId))
                        done()
                    }
                }
            }

            // RSA10i
            context("should adhere to all requirements relating to") {

                it("TokenParams") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "client_string"
                    let rest = ARTRest(options: options)

                    let tokenParams = ARTTokenParams()
                    tokenParams.clientId = ExpectedTokenParams.clientId
                    tokenParams.ttl = ExpectedTokenParams.ttl as NSNumber
                    tokenParams.capability = ExpectedTokenParams.capability

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(tokenParams, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                XCTFail("TokenDetails is nil"); done(); return
                            }
                            expect(tokenDetails).to(beAnInstanceOf(ARTTokenDetails.self))
                            expect(tokenDetails.token).toNot(beEmpty())
                            expect(tokenDetails.clientId).to(equal(ExpectedTokenParams.clientId))
                            expect(tokenDetails.issued!.addingTimeInterval(ExpectedTokenParams.ttl)).to(beCloseTo(tokenDetails.expires!))
                            expect(tokenDetails.capability).to(equal(ExpectedTokenParams.capability))
                            done()
                        }
                    }
                }

                it("authCallback") {
                    var currentTokenRequest: ARTTokenRequest? = nil

                    var rest = ARTRest(options: AblyTests.commonAppSetup())
                    rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, error in
                        currentTokenRequest = tokenRequest
                    })
                    expect(currentTokenRequest).toEventuallyNot(beNil(), timeout: testTimeout)

                    if currentTokenRequest == nil {
                        return
                    }

                    let options = AblyTests.clientOptions()
                    options.authCallback = { tokenParams, completion in
                        completion(currentTokenRequest!, nil)
                    }

                    rest = ARTRest(options: options)
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                XCTFail("TokenDetails is nil"); done(); return
                            }
                            expect(tokenDetails).to(beAnInstanceOf(ARTTokenDetails.self))
                            expect(tokenDetails.token).toNot(beEmpty())
                            expect(tokenDetails.expires!.timeIntervalSinceNow).to(beGreaterThan(tokenDetails.issued!.timeIntervalSinceNow))
                            done()
                        }
                    }
                }

                it("authUrl") {
                    let options = ARTClientOptions()
                    options.authUrl = URL(string: "http://echo.ably.io")!

                    let rest = ARTRest(options: options)
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            guard let error = error as? ARTErrorInfo else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error.statusCode).to(equal(400)) //Bad request
                            expect(tokenDetails).to(beNil())
                            done()
                        }
                    }
                }

                it("authUrl with json") {
                    guard let tokenDetails = getTestTokenDetails() else {
                        XCTFail("TokenDetails is empty")
                        return
                    }

                    let encoder = ARTJsonLikeEncoder()
                    encoder.delegate = ARTJsonEncoder()
                    guard let tokenDetailsJSON = String(data: try! encoder.encode(tokenDetails), encoding: .utf8) else {
                        XCTFail("JSON TokenDetails is empty")
                        return
                    }

                    let options = ARTClientOptions()
                    // Use authUrl for authentication with JSON TokenDetails response
                    options.authUrl = URL(string: "http://echo.ably.io")!
                    options.authParams = [URLQueryItem]()
                    options.authParams?.append(URLQueryItem(name: "type", value: "json"))
                    options.authParams?.append(URLQueryItem(name: "body", value: "[]"))
                    var rest = ARTRest(options: options)

                    // Invalid TokenDetails
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect((error as! ARTErrorInfo).code).to(equal(Int(ARTState.authUrlIncompatibleContent.rawValue)))
                            expect(tokenDetails).to(beNil())
                            done()
                        }
                    }

                    options.authParams?.removeLast()
                    options.authParams?.append(URLQueryItem(name: "body", value: tokenDetailsJSON))
                    rest = ARTRest(options: options)

                    // Valid token
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            done()
                        }
                    }
                }

                // https://github.com/ably/ably-cocoa/issues/618
                it("authUrl returning TokenRequest decodes TTL as expected") {
                    let options = AblyTests.commonAppSetup()

                    var rest = ARTRest(options: options)
                    var tokenRequest: ARTTokenRequest!
                    waitUntil(timeout: testTimeout) { done in
                        let params = ARTTokenParams(clientId: "myClientId", nonce: "12345")
                        expect(params.ttl).to(beNil())
                        rest.auth.createTokenRequest(params, options: nil) { req, _ in
                            expect(req!.ttl).to(beNil())
                            tokenRequest = req!
                            done()
                        }
                    }

                    let encoder = ARTJsonLikeEncoder()
                    encoder.delegate = ARTJsonEncoder()
                    let encodedTokenRequest: Data
                    do {
                        encodedTokenRequest = try encoder.encode(tokenRequest)
                    }
                    catch {
                        fail("Encode failure: \(error)")
                        return
                    }
                    guard let tokenRequestJSON = String(data: encodedTokenRequest, encoding: .utf8) else {
                        XCTFail("JSON Token Request is empty")
                        return
                    }

                    options.authUrl = URL(string: "http://echo.ably.io")!
                    options.authParams = [URLQueryItem]()
                    options.authParams?.append(URLQueryItem(name: "type", value: "json"))
                    options.authParams?.append(URLQueryItem(name: "body", value: tokenRequestJSON))
                    options.key = nil
                    rest = ARTRest(options: options)

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            expect(tokenDetails?.clientId).to(equal("myClientId"))
                            done()
                        }
                    }
                }

                it("authUrl with plain text") {
                    let token = getTestToken()
                    let options = ARTClientOptions()
                    // Use authUrl for authentication with plain text token response
                    options.authUrl = URL(string: "http://echo.ably.io")!
                    options.authParams = [URLQueryItem]()
                    options.authParams?.append(URLQueryItem(name: "type", value: "text"))
                    options.authParams?.append(URLQueryItem(name: "body", value: ""))
                    var rest = ARTRest(options: options)

                    // Invalid token
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).toNot(beNil())
                            expect(tokenDetails).to(beNil())
                            done()
                        }
                    }

                    options.authParams?.removeLast()
                    options.authParams?.append(URLQueryItem(name: "body", value: token))
                    rest = ARTRest(options: options)

                    // Valid token
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            done()
                        }
                    }
                }
                
            }

            // RSA10j
            context("when TokenParams and AuthOptions are provided") {

                it("should supersede configured AuthOptions (using key) even if arguments objects are empty") {
                    let defaultOptions = AblyTests.clientOptions() //sandbox
                    defaultOptions.key = "xxxx:xxxx"
                    let rest = ARTRest(options: defaultOptions)

                    let authOptions = ARTAuthOptions()
                    authOptions.key = AblyTests.commonAppSetup().key //valid key
                    let tokenParams = ARTTokenParams()
                    tokenParams.ttl = 1.0

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(tokenParams, options: authOptions) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let issued = tokenDetails?.issued else {
                                fail("TokenDetails.issued is nil"); done(); return
                            }
                            guard let expires = tokenDetails?.expires else {
                                fail("TokenDetails.expires is nil"); done(); return
                            }
                            expect(issued).to(beCloseTo(expires, within: tokenParams.ttl as! TimeInterval + 0.1))
                            delay(tokenParams.ttl as! TimeInterval + 0.1) {
                                done()
                            }
                        }
                    }

                    authOptions.key = nil
                    // First time
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: authOptions) { _, error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error.localizedDescription).to(contain("no means to renew the token"))
                            done()
                        }
                    }

                    // Second time
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { _, error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error.localizedDescription).to(contain("no means to renew the token"))
                            done()
                        }
                    }
                }

                it("should supersede configured AuthOptions (using authUrl) even if arguments objects are empty") {
                    let rest = ARTRest(options: AblyTests.commonAppSetup())

                    let testTokenDetails = getTestTokenDetails(ttl: 0.1)
                    let encoder = ARTJsonLikeEncoder()
                    encoder.delegate = ARTJsonEncoder()
                    guard let currentTokenDetails = testTokenDetails, let jsonTokenDetails = try? encoder.encode(currentTokenDetails) else {
                        fail("Invalid TokenDetails")
                        return
                    }

                    let authOptions = ARTAuthOptions()
                    authOptions.authUrl = URL(string: "http://echo.ably.io")!
                    authOptions.authParams = [URLQueryItem]()
                    authOptions.authParams?.append(URLQueryItem(name: "type", value: "json"))
                    authOptions.authParams?.append(URLQueryItem(name: "body", value: jsonTokenDetails.toUTF8String))
                    authOptions.authHeaders = ["X-Ably":"Test"]

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                XCTFail("TokenDetails is nil"); done(); return
                            }
                            expect(tokenDetails.token).to(equal(currentTokenDetails.token))
                            expect(rest.auth.internal.options.authUrl).toNot(beNil())
                            expect(rest.auth.internal.options.authParams).toNot(beNil())
                            expect(rest.auth.internal.options.authHeaders).toNot(beNil())
                            delay(0.1) { //force to use the authUrl again
                                done()
                            }
                        }
                    }

                    authOptions.authParams = nil
                    authOptions.authHeaders = nil
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                            guard let error = error as? ARTErrorInfo else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error.statusCode).to(equal(400))
                            expect(tokenDetails).to(beNil())
                            expect(rest.auth.internal.options.authParams).to(beNil())
                            expect(rest.auth.internal.options.authHeaders).to(beNil())
                            done()
                        }
                    }

                    // Repeat
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            guard let error = error as? ARTErrorInfo else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error.statusCode).to(equal(400))
                            expect(tokenDetails).to(beNil())
                            expect(rest.auth.internal.options.authParams).to(beNil())
                            expect(rest.auth.internal.options.authHeaders).to(beNil())
                            done()
                        }
                    }

                    authOptions.authUrl = nil
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(UInt((error as! ARTErrorInfo).code)).to(equal(ARTState.requestTokenFailed.rawValue))
                            expect(tokenDetails).to(beNil())
                            expect(rest.auth.internal.options.authUrl).to(beNil())
                            expect(rest.auth.internal.options.authParams).to(beNil())
                            expect(rest.auth.internal.options.authHeaders).to(beNil())
                            done()
                        }
                    }

                    // Repeat
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(UInt((error as! ARTErrorInfo).code)).to(equal(ARTState.requestTokenFailed.rawValue))
                            expect(tokenDetails).to(beNil())
                            expect(rest.auth.internal.options.authUrl).to(beNil())
                            expect(rest.auth.internal.options.authParams).to(beNil())
                            expect(rest.auth.internal.options.authHeaders).to(beNil())
                            done()
                        }
                    }
                }

                it("should supersede configured AuthOptions (using authCallback) even if arguments objects are empty") {
                    let rest = ARTRest(options: AblyTests.commonAppSetup())

                    let testTokenDetails = ARTTokenDetails(token: "token", expires: Date(), issued: Date(), capability: nil, clientId: nil)
                    var authCallbackHasBeenInvoked = false
                    let authOptions = ARTAuthOptions()
                    authOptions.authCallback = { tokenParams, completion in
                        authCallbackHasBeenInvoked = true
                        completion(testTokenDetails, nil)
                    }

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails?.token).to(equal("token"))
                            expect(authCallbackHasBeenInvoked).to(beTrue())
                            expect(rest.auth.internal.options.authCallback).toNot(beNil())
                            done()
                        }
                    }
                    authCallbackHasBeenInvoked = false

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails?.token).to(equal("token"))
                            expect(authCallbackHasBeenInvoked).to(beTrue())
                            expect(rest.auth.internal.options.authCallback).toNot(beNil())
                            done()
                        }
                    }
                    authCallbackHasBeenInvoked = false

                    authOptions.authCallback = nil
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(UInt((error as! ARTErrorInfo).code)).to(equal(ARTState.requestTokenFailed.rawValue))
                            expect(tokenDetails).to(beNil())
                            expect(authCallbackHasBeenInvoked).to(beFalse())
                            expect(rest.auth.internal.options.authCallback).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(UInt((error as! ARTErrorInfo).code)).to(equal(ARTState.requestTokenFailed.rawValue))
                            expect(tokenDetails).to(beNil())
                            expect(authCallbackHasBeenInvoked).to(beFalse())
                            expect(rest.auth.internal.options.authCallback).to(beNil())
                            done()
                        }
                    }
                }

                it("should supersede configured params and options even if arguments objects are empty") {
                    let options = AblyTests.clientOptions()
                    options.key = "xxxx:xxxx"
                    options.clientId = "client_string"
                    let rest = ARTRest(options: options)

                    let tokenParams = ARTTokenParams(clientId: options.clientId)

                    // Defaults
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect((error as! ARTErrorInfo).code).to(equal(40400))
                            expect(tokenDetails).to(beNil())
                            done()
                        }
                    }

                    // Custom
                    tokenParams.ttl = ExpectedTokenParams.ttl as NSNumber
                    tokenParams.capability = ExpectedTokenParams.capability
                    tokenParams.clientId = nil

                    let authOptions = ARTAuthOptions()
                    authOptions.key = AblyTests.commonAppSetup().key
                    authOptions.queryTime = true

                    var serverTimeRequestCount = 0
                    let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(_:))) {
                        serverTimeRequestCount += 1
                    }
                    defer { hook.remove() }

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(tokenParams, options: authOptions) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                XCTFail("TokenDetails is nil"); done(); return
                            }
                            expect(tokenDetails.clientId).to(beNil())
                            expect(tokenDetails.issued!.addingTimeInterval(ExpectedTokenParams.ttl)).to(beCloseTo(tokenDetails.expires!))
                            expect(tokenDetails.capability).to(equal(ExpectedTokenParams.capability))
                            expect(serverTimeRequestCount) == 1
                            done()
                        }
                    }

                    rest.auth.internal.testSuite_forceTokenToExpire()

                    // Subsequent authorisations
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is nil"); done(); return
                            }
                            expect(tokenDetails.clientId).to(beNil())
                            expect(tokenDetails.issued!.addingTimeInterval(ExpectedTokenParams.ttl)).to(beCloseTo(tokenDetails.expires!))
                            expect(tokenDetails.capability).to(equal(ExpectedTokenParams.capability))
                            expect(serverTimeRequestCount) == 1
                            done()
                        }
                    }
                }

                it("example: if a client is initialised with TokenParams#ttl configured with a custom value, and a TokenParams object is passed in as an argument to #authorize with a null value for ttl, then the ttl used for every subsequent authorization will be null") {
                    let options = AblyTests.commonAppSetup()
                    options.defaultTokenParams = {
                        $0.ttl = 0.1;
                        $0.clientId = "tester";
                        return $0
                    }(ARTTokenParams())

                    let rest = ARTRest(options: options)

                    let testTokenParams = ARTTokenParams()
                    testTokenParams.ttl = nil
                    testTokenParams.clientId = nil

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(testTokenParams, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is nil"); done(); return
                            }
                            guard let issued = tokenDetails.issued else {
                                fail("TokenDetails.issued is nil"); done(); return
                            }
                            guard let expires = tokenDetails.expires else {
                                fail("TokenDetails.expires is nil"); done(); return
                            }
                            expect(tokenDetails.clientId).to(beNil())
                            // `ttl` when omitted, the default value is applied
                            expect(issued.addingTimeInterval(ARTDefault.ttl())).to(equal(expires))
                            done()
                        }
                    }

                    // Subsequent authorization
                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is nil"); done(); return
                            }
                            guard let issued = tokenDetails.issued else {
                                fail("TokenDetails.issued is nil"); done(); return
                            }
                            guard let expires = tokenDetails.expires else {
                                fail("TokenDetails.expires is nil"); done(); return
                            }
                            expect(tokenDetails.clientId).to(beNil())
                            expect(issued.addingTimeInterval(ARTDefault.ttl())).to(equal(expires))
                            done()
                        }
                    }
                }

            }
            
            // RSA10k
            context("server time offset") {

                xit("should obtain server time once and persist the offset from the local clock") {
                    let options = AblyTests.commonAppSetup()
                    let rest = ARTRest(options: options)

                    let mockServerDate = Date().addingTimeInterval(120)
                    rest.auth.internal.testSuite_returnValue(for: NSSelectorFromString("handleServerTime:"), with: mockServerDate)
                    let currentDate = Date()

                    var serverTimeRequestCount = 0
                    let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(_:))) {
                        serverTimeRequestCount += 1
                    }
                    defer { hook.remove() }

                    let authOptions = ARTAuthOptions()
                    authOptions.key = options.key
                    authOptions.queryTime = true

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: authOptions, callback: { tokenDetails, error in
                            expect(error).to(beNil())
                            guard tokenDetails != nil else {
                                fail("TokenDetails is nil"); done(); return
                            }
                            guard let timeOffset = rest.auth.internal.timeOffset?.doubleValue else {
                                fail("Server Time Offset is nil"); done(); return
                            }
                            expect(timeOffset).toNot(equal(0))
                            expect(rest.auth.internal.timeOffset).toNot(beNil())
                            let calculatedServerDate = currentDate.addingTimeInterval(timeOffset)
                            expect(calculatedServerDate).to(beCloseTo(mockServerDate, within: 0.9))
                            expect(serverTimeRequestCount) == 1
                            done()
                        })
                    }

                    rest.auth.internal.testSuite_forceTokenToExpire()

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard tokenDetails != nil else {
                                fail("TokenDetails is nil"); done(); return
                            }
                            guard let timeOffset = rest.auth.internal.timeOffset?.doubleValue else {
                                fail("Server Time Offset is nil"); done(); return
                            }
                            expect(timeOffset).toNot(equal(0))
                            let calculatedServerDate = currentDate.addingTimeInterval(timeOffset)
                            expect(calculatedServerDate).to(beCloseTo(mockServerDate, within: 0.9))
                            expect(serverTimeRequestCount) == 1
                            done()
                        }
                    }
                }

                it("should be consistent the timestamp request with the server time") {
                    let options = AblyTests.commonAppSetup()
                    let rest = ARTRest(options: options)

                    let mockServerDate = Date().addingTimeInterval(120)
                    rest.auth.internal.testSuite_returnValue(for: NSSelectorFromString("handleServerTime:"), with: mockServerDate)

                    var serverTimeRequestCount = 0
                    let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(_:))) {
                        serverTimeRequestCount += 1
                    }
                    defer { hook.remove() }

                    let authOptions = ARTAuthOptions()
                    authOptions.key = options.key
                    authOptions.queryTime = true

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.createTokenRequest(nil, options: authOptions) { tokenRequest, error in
                            expect(error).to(beNil())
                            guard let tokenRequest = tokenRequest else {
                                fail("TokenRequest is nil"); done(); return
                            }
                            guard let timeOffset = rest.auth.internal.timeOffset?.doubleValue else {
                                fail("Server Time Offset is nil"); done(); return
                            }
                            expect(timeOffset).toNot(equal(0))
                            expect(mockServerDate.timeIntervalSinceNow).to(beCloseTo(timeOffset, within: 0.1))
                            expect(tokenRequest.timestamp).to(beCloseTo(mockServerDate))
                            expect(serverTimeRequestCount) == 1
                            done()
                        }
                    }
                }

                it("should be possible by lib Client to discard the cached local clock offset") {
                    let options = AblyTests.commonAppSetup()
                    options.queryTime = true
                    let rest = ARTRest(options: options)

                    var serverTimeRequestCount = 0
                    let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(_:))) {
                        serverTimeRequestCount += 1
                    }
                    defer { hook.remove() }

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard let tokenDetails = tokenDetails else {
                                fail("TokenDetails is nil"); done(); return
                            }
                            guard let timeOffset = rest.auth.internal.timeOffset?.doubleValue else {
                                fail("Server Time Offset is nil"); done(); return
                            }
                            expect(timeOffset).toNot(beCloseTo(0))
                            let calculatedServerDate = Date().addingTimeInterval(timeOffset)
                            expect(tokenDetails.expires).to(beCloseTo(calculatedServerDate.addingTimeInterval(ARTDefault.ttl()), within: 1.0))
                            expect(serverTimeRequestCount) == 1
                            done()
                        }
                    }

                    #if TARGET_OS_IPHONE
                    NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: nil)
                    #else
                    NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
                    #endif

                    rest.auth.internal.testSuite_forceTokenToExpire()

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                            expect(error).to(beNil())
                            guard tokenDetails != nil else {
                                fail("TokenDetails is nil"); done(); return
                            }
                            expect(rest.auth.internal.timeOffset).to(beNil())
                            expect(serverTimeRequestCount) == 1
                            done()
                        }
                    }
                }

                it("should use the local clock offset to calculate the server time") {
                    let options = AblyTests.commonAppSetup()
                    let rest = ARTRest(options: options)

                    let authOptions = ARTAuthOptions()
                    authOptions.key = options.key
                    authOptions.queryTime = false

                    let fakeOffset: TimeInterval = 60 //1 minute
                    rest.auth.internal.setTimeOffset(fakeOffset)

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.createTokenRequest(nil, options: authOptions) { tokenRequest, error in
                            expect(error).to(beNil())
                            guard let tokenRequest = tokenRequest else {
                                fail("TokenRequest is nil"); done(); return
                            }
                            guard let timeOffset = rest.auth.internal.timeOffset?.doubleValue else {
                                fail("Server Time Offset is nil"); done(); return
                            }
                            expect(timeOffset) == fakeOffset
                            let calculatedServerDate = Date().addingTimeInterval(timeOffset)
                            expect(tokenRequest.timestamp).to(beCloseTo(calculatedServerDate, within: 0.5))
                            done()
                        }
                    }
                }

                it("should request server time when queryTime is true even if the time offset is assigned") {
                    let options = AblyTests.commonAppSetup()
                    let rest = ARTRest(options: options)

                    var serverTimeRequestCount = 0
                    let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time)) {
                        serverTimeRequestCount += 1
                    }
                    defer { hook.remove() }

                    let fakeOffset: TimeInterval = 60 //1 minute
                    rest.auth.internal.setTimeOffset(fakeOffset)

                    let authOptions = ARTAuthOptions()
                    authOptions.key = options.key
                    authOptions.queryTime = true

                    waitUntil(timeout: testTimeout) { done in
                        rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                            expect(error).to(beNil())
                            expect(tokenDetails).toNot(beNil())
                            expect(serverTimeRequestCount) == 1
                            guard let timeOffset = rest.auth.internal.timeOffset?.doubleValue else {
                                fail("Server Time Offset is nil"); done(); return
                            }
                            expect(timeOffset).toNot(equal(fakeOffset))
                            done()
                        }
                    }
                }

                it("should discard the time offset in situations in which it may have been invalidated") {
                    let rest = ARTRest(options: AblyTests.commonAppSetup())

                    var discardTimeOffsetCallCount = 0
                    let hook = rest.auth.internal.testSuite_injectIntoMethod(after: #selector(rest.auth.internal.discardTimeOffset)) {
                        discardTimeOffsetCallCount += 1
                    }
                    defer { hook.remove() }

                    #if TARGET_OS_IPHONE
                    // Force notification
                    NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: nil)

                    expect(discardTimeOffsetCallCount).toEventually(equal(1), timeout: testTimeout)

                    // Force notification
                    NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
                    #else
                    // Force notification
                    NotificationCenter.default.post(name: NSNotification.Name.NSSystemClockDidChange, object: nil)

                    expect(discardTimeOffsetCallCount).toEventually(equal(1), timeout: testTimeout)

                    // Force notification
                    NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
                    #endif

                    expect(discardTimeOffsetCallCount).toEventually(equal(2), timeout: testTimeout)
                }

            }

            context("two consecutive authorizations") {
                it("using REST, should call each authorize callback") {
                    let options = AblyTests.commonAppSetup()
                    options.useTokenAuth = true
                    let rest = ARTRest(options: options)

                    var tokenDetailsFirst: ARTTokenDetails?
                    var tokenDetailsLast: ARTTokenDetails?
                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        rest.auth.authorize { tokenDetails, error in
                            if let error = error {
                                fail(error.localizedDescription); partialDone(); return
                            }
                            expect(tokenDetails).toNot(beNil())
                            if tokenDetailsFirst == nil {
                                tokenDetailsFirst = tokenDetails
                            }
                            else {
                                tokenDetailsLast = tokenDetails
                            }
                            partialDone()
                        }
                        rest.auth.authorize { tokenDetails, error in
                            if let error = error {
                                fail(error.localizedDescription); partialDone(); return
                            }
                            expect(tokenDetails).toNot(beNil())
                            if tokenDetailsFirst == nil {
                                tokenDetailsFirst = tokenDetails
                            }
                            else {
                                tokenDetailsLast = tokenDetails
                            }
                            partialDone()
                        }
                    }

                    expect(tokenDetailsFirst?.token).toNot(equal(tokenDetailsLast?.token))
                    expect(rest.auth.tokenDetails).to(beIdenticalTo(tokenDetailsLast))
                    expect(rest.auth.tokenDetails?.token).to(equal(tokenDetailsLast?.token))
                }
                it("using Realtime and connection is CONNECTING, should call each Realtime authorize callback") {
                    let options = AblyTests.commonAppSetup()
                    options.useTokenAuth = true
                    let realtime = AblyTests.newRealtime(options)
                    defer { realtime.close(); realtime.dispose() }

                    var connectedStateCount = 0
                    realtime.connection.on(.connected) { _ in
                        connectedStateCount += 1
                    }

                    var tokenDetailsFirst: ARTTokenDetails?
                    var tokenDetailsLast: ARTTokenDetails?
                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        realtime.auth.authorize { tokenDetails, error in
                            if let error = error, (error as NSError).code != URLError.cancelled.rawValue {
                                fail(error.localizedDescription); partialDone(); return
                            }
                            expect(tokenDetails).toNot(beNil())
                            if tokenDetailsFirst == nil {
                                tokenDetailsFirst = tokenDetails
                            }
                            else {
                                tokenDetailsLast = tokenDetails
                            }
                            partialDone()
                        }
                        realtime.auth.authorize { tokenDetails, error in
                            if let error = error, (error as NSError).code != URLError.cancelled.rawValue {
                                fail(error.localizedDescription); partialDone(); return
                            }
                            expect(tokenDetails).toNot(beNil())
                            if tokenDetailsFirst == nil {
                                tokenDetailsFirst = tokenDetails
                            }
                            else {
                                tokenDetailsLast = tokenDetails
                            }
                            partialDone()
                        }
                    }

                    expect(tokenDetailsFirst?.token).toNot(equal(tokenDetailsLast?.token))
                    expect(realtime.auth.tokenDetails).to(beIdenticalTo(tokenDetailsLast))
                    expect(realtime.auth.tokenDetails?.token).to(equal(tokenDetailsLast?.token))

                    if let transport = realtime.internal.transport as? TestProxyTransport, let query = transport.lastUrl?.query {
                        expect(query).to(haveParam("accessToken", withValue: realtime.auth.tokenDetails?.token ?? ""))
                    }
                    else {
                        XCTFail("MockTransport is not working")
                    }

                    expect(connectedStateCount) == 1
                }
                it("using Realtime and connection is CONNECTED, should call each Realtime authorize callback") {
                    let options = AblyTests.commonAppSetup()
                    options.useTokenAuth = true
                    let realtime = ARTRealtime(options: options)
                    defer { realtime.close(); realtime.dispose() }

                    waitUntil(timeout: testTimeout) { done in
                        realtime.connection.once(.connected) { state in
                            done()
                        }
                    }

                    var tokenDetailsFirst: ARTTokenDetails?
                    var tokenDetailsLast: ARTTokenDetails?
                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        realtime.auth.authorize { tokenDetails, error in
                            if let error = error {
                                fail(error.localizedDescription); partialDone(); return
                            }
                            expect(tokenDetails).toNot(beNil())
                            if tokenDetailsFirst == nil {
                                tokenDetailsFirst = tokenDetails
                            }
                            else {
                                tokenDetailsLast = tokenDetails
                            }
                            partialDone()
                        }
                        realtime.auth.authorize { tokenDetails, error in
                            if let error = error {
                                fail(error.localizedDescription); partialDone(); return
                            }
                            expect(tokenDetails).toNot(beNil())
                            if tokenDetailsFirst == nil {
                                tokenDetailsFirst = tokenDetails
                            }
                            else {
                                tokenDetailsLast = tokenDetails
                            }
                            partialDone()
                        }
                    }

                    expect(tokenDetailsFirst?.token).toNot(equal(tokenDetailsLast?.token))
                    expect(realtime.auth.tokenDetails).to(beIdenticalTo(tokenDetailsLast))
                    expect(realtime.auth.tokenDetails?.token).to(equal(tokenDetailsLast?.token))
                }
            }

        }

        describe("TokenParams") {
            context("timestamp") {
                it("if explicitly set, should be returned by the getter") {
                    let params = ARTTokenParams()
                    params.timestamp = Date(timeIntervalSince1970: 123)
                    expect(params.timestamp).to(equal(Date(timeIntervalSince1970: 123)))
                }

                it("if explicitly set, the value should stick") {
                    let params = ARTTokenParams()
                    params.timestamp = Date()

                    waitUntil(timeout: testTimeout) { done in
                        let now = Double(NSDate().artToIntegerMs())
                        guard let timestamp = params.timestamp else {
                            fail("timestamp is nil"); done(); return
                        }
                        let firstParamsTimestamp = Double((timestamp as NSDate).artToIntegerMs())
                        expect(firstParamsTimestamp).to(beCloseTo(now, within: 2.5))
                        delay(0.25) {
                            expect(Double((timestamp as NSDate).artToIntegerMs())).to(equal(firstParamsTimestamp))
                            done()
                        }
                    }
                }

                // https://github.com/ably/ably-cocoa/pull/508#discussion_r82577728
                it("object has no timestamp value unless explicitly set") {
                    let params = ARTTokenParams()
                    expect(params.timestamp).to(beNil())
                }
            }
        }

        describe("Reauth") {

            // RTC8
            it("should use authorize({force: true}) to reauth with a token with a different set of capabilities") {
                let options = AblyTests.commonAppSetup()
                let initialToken = getTestToken(clientId: "tester", capability: "{\"restricted\":[\"*\"]}")
                options.token = initialToken
                let realtime = ARTRealtime(options: options)
                defer { realtime.dispose(); realtime.close() }
                let channel = realtime.channels.get("foo")

                waitUntil(timeout: testTimeout) { done in
                    channel.attach { error in
                        guard let error = error else {
                            fail("Error is nil"); done(); return
                        }
                        expect(error.code) == 40160
                        done()
                    }
                }

                let tokenParams = ARTTokenParams()
                tokenParams.capability = "{\"\(channel.name)\":[\"*\"]}"
                tokenParams.clientId = "tester"

                waitUntil(timeout: testTimeout) { done in
                    realtime.auth.authorize(tokenParams, options: nil) { tokenDetails, error in
                        expect(error).to(beNil())
                        expect(tokenDetails).toNot(beNil())
                        done()
                    }
                }

                expect(realtime.auth.tokenDetails?.token).toNot(equal(initialToken))
                expect(realtime.auth.tokenDetails?.capability).to(equal(tokenParams.capability))

                waitUntil(timeout: testTimeout) { done in
                    channel.attach { error in
                        expect(error).to(beNil())
                        done()
                    }
                }
            }

            // RTC8
            it("for a token change that fails due to an incompatible token, which should result in the connection entering the FAILED state") {
                let options = AblyTests.commonAppSetup()
                options.clientId = "tester"
                options.useTokenAuth = true
                let realtime = ARTRealtime(options: options)
                defer { realtime.dispose(); realtime.close() }

                waitUntil(timeout: testTimeout) { done in
                    realtime.connection.on(.connected) { stateChange in
                        expect(stateChange?.reason).to(beNil())
                        done()
                    }
                }

                guard let initialToken = realtime.auth.tokenDetails?.token else {
                    fail("TokenDetails is nil"); return
                }

                let tokenParams = ARTTokenParams()
                tokenParams.capability = "{\"restricted\":[\"*\"]}"
                tokenParams.clientId = "secret"

                waitUntil(timeout: testTimeout) { done in
                    realtime.auth.authorize(tokenParams, options: nil) { tokenDetails, error in
                        guard let error = error else {
                            fail("Error is nil"); done(); return
                        }
                        expect((error as! ARTErrorInfo).code) == 40102
                        expect(tokenDetails).to(beNil())
                        done()
                    }
                }

                expect(realtime.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
                expect(realtime.auth.tokenDetails?.token).to(equal(initialToken))
                expect(realtime.auth.tokenDetails?.capability).toNot(equal(tokenParams.capability))
            }

        }

        describe("TokenParams") {
            // TK2d
            it("timestamp should not be a member of any default token params") {
                let rest = ARTRest(options: AblyTests.commonAppSetup())
                waitUntil(timeout: testTimeout) { done in
                    rest.auth.authorize(nil, options: nil) { _, error in
                        expect(error).to(beNil())
                        guard let defaultTokenParams = rest.auth.internal.options.defaultTokenParams else {
                            fail("DefaultTokenParams is nil"); done(); return
                        }
                        expect(defaultTokenParams.timestamp).to(beNil())

                        var defaultTokenParamsCallCount = 0
                        let hook = rest.auth.internal.options.testSuite_injectIntoMethod(after: NSSelectorFromString("defaultTokenParams")) {
                            defaultTokenParamsCallCount += 1
                        }
                        defer { hook.remove() }

                        let newTokenParams = ARTTokenParams(options: rest.auth.internal.options)
                        expect(defaultTokenParamsCallCount) > 0

                        newTokenParams.timestamp = Date()
                        expect(newTokenParams.timestamp).toNot(beNil())
                        expect(defaultTokenParams.timestamp).to(beNil()) //remain nil
                        done()
                    }
                }
            }
        }

        describe("TokenRequest") {
            // TE6
            describe("fromJson") {
                let cases = [
                    "with TTL": (
                        "{" +
                        "    \"clientId\":\"myClientId\"," +
                        "    \"mac\":\"4rr4J+JzjiCL1DoS8wq7k11Z4oTGCb1PoeN+yGjkaH4=\"," +
                        "    \"capability\":\"{\\\"test\\\":[\\\"publish\\\"]}\"," +
                        "    \"ttl\":42000," +
                        "    \"timestamp\":1479087321934," +
                        "    \"keyName\":\"xxxxxx.yyyyyy\"," +
                        "    \"nonce\":\"7830658976108826\"" +
                        "}",
                        { (_ request: ARTTokenRequest) in
                            expect(request.clientId).to(equal("myClientId"))
                            expect(request.mac).to(equal("4rr4J+JzjiCL1DoS8wq7k11Z4oTGCb1PoeN+yGjkaH4="))
                            expect(request.capability).to(equal("{\"test\":[\"publish\"]}"))
                            expect(request.ttl as? TimeInterval).to(equal(TimeInterval(42)))
                            expect(request.timestamp).to(equal(Date(timeIntervalSince1970: 1479087321.934)))
                            expect(request.keyName).to(equal("xxxxxx.yyyyyy"))
                            expect(request.nonce).to(equal("7830658976108826"))
                        }
                    ),
                    "without TTL": (
                        "{" +
                        "    \"mac\":\"4rr4J+JzjiCL1DoS8wq7k11Z4oTGCb1PoeN+yGjkaH4=\"," +
                        "    \"capability\":\"{\\\"test\\\":[\\\"publish\\\"]}\"," +
                        "    \"timestamp\":1479087321934," +
                        "    \"keyName\":\"xxxxxx.yyyyyy\"," +
                        "    \"nonce\":\"7830658976108826\"" +
                        "}",
                        { (_ request: ARTTokenRequest) in
                            expect(request.clientId).to(beNil())
                            expect(request.mac).to(equal("4rr4J+JzjiCL1DoS8wq7k11Z4oTGCb1PoeN+yGjkaH4="))
                            expect(request.capability).to(equal("{\"test\":[\"publish\"]}"))
                            expect(request.ttl).to(beNil())
                            expect(request.timestamp).to(equal(Date(timeIntervalSince1970: 1479087321.934)))
                            expect(request.keyName).to(equal("xxxxxx.yyyyyy"))
                            expect(request.nonce).to(equal("7830658976108826"))
                        }
                    )
                ]

                for (caseName, (json, check)) in cases {
                    context(caseName) {
                        it("accepts a string, which should be interpreted as JSON") {
                            check(try! ARTTokenRequest.fromJson(json as ARTJsonCompatible))
                        }

                        it("accepts a NSDictionary") {
                            let data = json.data(using: String.Encoding.utf8)!
                            let dict = try! JSONSerialization.jsonObject(with: data, options: .mutableLeaves) as! NSDictionary
                            check(try! ARTTokenRequest.fromJson(dict))
                        }
                    }
                }

                it("rejects invalid JSON") {
                    expect{try ARTTokenRequest.fromJson("not JSON" as ARTJsonCompatible)}.to(throwError())
                }

                it("rejects non-object JSON") {
                    expect{try ARTTokenRequest.fromJson("[]" as ARTJsonCompatible)}.to(throwError())
                }
            }
        }

        describe("TokenDetails") {
            // TD7
            describe("fromJson") {
                let json = "{" +
                "    \"token\": \"xxxxxx.yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy\"," +
                "    \"issued\": 1479087321934," +
                "    \"expires\": 1479087363934," +
                "    \"capability\": \"{\\\"test\\\":[\\\"publish\\\"]}\"," +
                "    \"clientId\": \"myClientId\"" +
                "}"

                func check(_ details: ARTTokenDetails) {
                    expect(details.token).to(equal("xxxxxx.yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"))
                    expect(details.issued).to(equal(Date(timeIntervalSince1970: 1479087321.934)))
                    expect(details.expires).to(equal(Date(timeIntervalSince1970: 1479087363.934)))
                    expect(details.capability).to(equal("{\"test\":[\"publish\"]}"))
                    expect(details.clientId).to(equal("myClientId"))
                }

                it("accepts a string, which should be interpreted as JSON") {
                    check(try! ARTTokenDetails.fromJson(json as ARTJsonCompatible))
                }

                it("accepts a NSDictionary") {
                    let data = json.data(using: String.Encoding.utf8)!
                    let dict = try! JSONSerialization.jsonObject(with: data, options: .mutableLeaves) as! NSDictionary
                    check(try! ARTTokenDetails.fromJson(dict))
                }

                it("rejects invalid JSON") {
                    expect{try ARTTokenDetails.fromJson("not JSON" as ARTJsonCompatible)}.to(throwError())
                }

                it("rejects non-object JSON") {
                    expect{try ARTTokenDetails.fromJson("[]" as ARTJsonCompatible)}.to(throwError())
                }
            }
        }

        describe("JWT and realtime") {
            let channelName = "test_JWT"
            let messageName = "message_JWT"
            
            context("client initialized with a JWT token in ClientOptions") {
                let options = AblyTests.clientOptions()

                context("with valid credentials") {
                    xit("pulls stats successfully") {
                        options.token = getJWTToken()
                        let client = AblyTests.newRealtime(options)
                        defer { client.dispose(); client.close() }

                        waitUntil(timeout: testTimeout) { done in
                            client.stats { stats, error in
                                expect(error).to(beNil())
                                done()
                            }
                        }
                    }
                }

                context("with invalid credentials") {
                    it("fails to connect with reason 'invalid signature'") {
                        options.token = getJWTToken(invalid: true)
                        options.autoConnect = false
                        let client = AblyTests.newRealtime(options)
                        defer { client.dispose(); client.close() }

                        waitUntil(timeout: testTimeout) { done in
                            client.connection.once(.failed) { stateChange in
                                guard let reason = stateChange?.reason else {
                                    fail("Reason error is nil"); done(); return
                                }
                                expect(reason.code).to(equal(40144))
                                expect(reason.description).to(satisfyAnyOf(contain("invalid signature"), contain("signature verification failed")))
                                done()
                            }
                            client.connect()
                        }
                    }
                }
            }

            // RSA8g RSA8c
            context("when using authUrl") {
                let options = AblyTests.clientOptions()
                options.authUrl = URL(string: echoServerAddress)!

                var keys: [String: String]!

                func setupDependencies() {
                    if (keys == nil) {
                        keys = getKeys()
                    }
                }

                context("with valid credentials") {
                    it("fetches a channels and posts a message") {
                        setupDependencies()

                        options.authParams = [URLQueryItem]()
                        options.authParams?.append(URLQueryItem(name: "keyName", value: keys["keyName"]))
                        options.authParams?.append(URLQueryItem(name: "keySecret", value: keys["keySecret"]))
                        let client = ARTRealtime(options: options)
                        defer { client.dispose(); client.close() }

                        waitUntil(timeout: testTimeout) { done in
                            client.connection.once(.connected, callback: { _ in
                                let channel = client.channels.get(channelName)
                                channel.publish(messageName, data: nil, callback: { error in
                                    expect(error).to(beNil())
                                    done()
                                })
                            })
                            client.connect()
                        }
                    }
                }

                context("with wrong credentials") {
                    it("fails to connect with reason 'invalid signature'") {
                        setupDependencies()

                        options.authParams = [URLQueryItem]()
                        options.authParams?.append(URLQueryItem(name: "keyName", value: keys["keyName"]))
                        options.authParams?.append(URLQueryItem(name: "keySecret", value: "INVALID"))
                        let client = ARTRealtime(options: options)
                        defer { client.dispose(); client.close() }

                        waitUntil(timeout: testTimeout) { done in
                            client.connection.once(.disconnected) { stateChange in
                                guard let reason = stateChange?.reason else {
                                    fail("Reason error is nil"); done(); return
                                }
                                expect(reason.code).to(equal(40144))
                                expect(reason.description).to(satisfyAnyOf(contain("invalid signature"), contain("signature verification failed")))
                                done()
                            }
                            client.connect()
                        }
                    }
                }

                context("when token expires") {

                    it ("receives a 40142 error from the server") {
                        setupDependencies()

                        let tokenDuration = 5.0
                        options.authParams = [URLQueryItem]()
                        options.authParams?.append(URLQueryItem(name: "keyName", value: keys["keyName"]))
                        options.authParams?.append(URLQueryItem(name: "keySecret", value: keys["keySecret"]))
                        options.authParams?.append(URLQueryItem(name: "expiresIn", value: String(UInt(tokenDuration))))
                        let client = ARTRealtime(options: options)
                        defer { client.dispose(); client.close() }
                        
                        waitUntil(timeout: testTimeout) { done in
                            client.connection.once(.connected) { stateChange in
                                client.connection.once(.disconnected) { stateChange in
                                    expect(stateChange!.reason?.code).to(equal(40142))
                                    expect(stateChange!.reason?.description).to(contain("Key/token status changed (expire)"))
                                    done()
                                }
                            }
                            client.connect()
                        }
                    }
                }
                
                // RTC8a4
                context("when the server sends and AUTH protocol message") {
                    it("client reauths correctly without going through a disconnection") {
                        setupDependencies()
                        
                        // The server sends an AUTH protocol message 30 seconds before a token expires
                        // We create a token that lasts 35 seconds, so there's room to receive the AUTH message
                        let tokenDuration = 35.0
                        options.authParams = [URLQueryItem]()
                        options.authParams?.append(URLQueryItem(name: "keyName", value: keys["keyName"]))
                        options.authParams?.append(URLQueryItem(name: "keySecret", value: keys["keySecret"]))
                        options.authParams?.append(URLQueryItem(name: "expiresIn", value: String(UInt(tokenDuration))))
                        options.autoConnect = false // Prevent auto connection so we can set the transport proxy
                        let client = ARTRealtime(options: options)
                        client.internal.setTransport(TestProxyTransport.self)
                        defer { client.dispose(); client.close() }
                        
                        waitUntil(timeout: testTimeout) { done in
                            client.connection.once(.connected) { stateChange in
                                let originalToken = client.auth.tokenDetails?.token
                                let transport = client.internal.transport as! TestProxyTransport
                                
                                client.connection.once(.update) { stateChange in
                                    expect(transport.protocolMessagesReceived.filter({ $0.action == .auth })).to(haveCount(1))
                                    expect(originalToken).toNot(equal(client.auth.tokenDetails?.token))
                                    done()
                                }
                            }
                            client.connect()
                        }
                    }
                }
            }

            // RSA8g
            context("when using authCallback") {
                let options = AblyTests.clientOptions()

                context("with valid credentials") {
                    xit("pulls stats successfully") {
                        options.authCallback = { tokenParams, completion in
                            let token = ARTTokenDetails(token: getJWTToken()!)
                            completion(token, nil)
                        }
                        let client = ARTRealtime(options: options)
                        defer { client.dispose(); client.close() }

                        waitUntil(timeout: testTimeout) { done in
                            client.stats { stats, error in
                                expect(error).to(beNil())
                                done()
                            }
                        }
                    }
                }

                context("with invalid credentials") {
                    it("fails to connect") {
                        options.authCallback = { tokenParams, completion in
                            let token = ARTTokenDetails(token: getJWTToken(invalid: true)!)
                            completion(token, nil)
                        }
                        let client = ARTRealtime(options: options)
                        defer { client.dispose(); client.close() }

                        waitUntil(timeout: testTimeout) { done in
                            client.connection.once(.disconnected) { stateChange in
                                guard let reason = stateChange?.reason else {
                                    fail("Reason error is nil"); done(); return
                                }
                                expect(reason.code).to(equal(40144))
                                expect(reason.description).to(satisfyAnyOf(contain("invalid signature"), contain("signature verification failed")))
                                done()
                            }
                            client.connect()
                        }
                    }
                }
            }

            context("when token expires and has a means to renew") {

                it("reconnects using authCallback and obtains a new token") {
                    let tokenDuration = 3.0
                    let options = AblyTests.clientOptions()
                    options.useTokenAuth = true
                    options.autoConnect = false
                    options.authCallback = { tokenParams, completion in
                        let token = ARTTokenDetails(token: getJWTToken(expiresIn: Int(tokenDuration))!)
                        completion(token, nil)
                    }
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    var originalToken = ""
                    var originalConnectionID = ""
                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { _ in
                            originalToken = client.auth.tokenDetails!.token
                            originalConnectionID = client.connection.id!

                            client.connection.once(.disconnected) { stateChange in
                                expect(stateChange!.reason?.code).to(equal(40142))

                                client.connection.once(.connected) { _ in
                                    expect(client.connection.id).to(equal(originalConnectionID))
                                    expect(client.auth.tokenDetails!.token).toNot(equal(originalToken))
                                    done()
                                }
                            }
                        }
                        client.connect()
                    }
                }
            }
            
            context("when the token request includes a clientId") {
                it("the clientId is the same specified in the JWT token request") {
                    let clientId = "JWTClientId"
                    let options = AblyTests.clientOptions()
                    options.tokenDetails = ARTTokenDetails(token: getJWTToken(clientId: clientId)!)
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }

                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { _ in
                            expect(client.auth.clientId).to(equal(clientId))
                            done()
                        }
                        client.connect()
                    }
                }
            }
            
            context("when the token request includes subscribe-only capabilities") {
                it("fails to publish to a channel with subscribe-only capability") {
                    let capability = "{\"\(channelName)\":[\"subscribe\"]}"
                    let options = AblyTests.clientOptions()
                    options.tokenDetails = ARTTokenDetails(token: getJWTToken(capability: capability)!)
                    // Prevent channel name to be prefixed by test-*
                    options.channelNamePrefix = nil
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }

                    waitUntil(timeout: testTimeout) { done in
                        client.channels.get(channelName).publish(messageName, data: nil, callback: { error in
                            expect(error?.code).to(equal(40160))
                            expect(error?.message).to(contain("permission denied"))
                            done()
                        })
                    }
                }
            }
        }

        // RSA11
        context("currentTokenDetails") {

            // RSA11b
            it("should hold a @TokenDetails@ instance in which only the @token@ attribute is populated with that token string") {
                let token = getTestToken()
                let rest = ARTRest(token: token)
                expect(rest.auth.tokenDetails?.token).to(equal(token))
            }

            // RSA11c
            it("should be set with the current token (if applicable) on instantiation and each time it is replaced") {
                let rest = ARTRest(options: AblyTests.commonAppSetup())
                expect(rest.auth.tokenDetails).to(beNil())
                var authenticatedTokenDetails: ARTTokenDetails?
                waitUntil(timeout: testTimeout) { done in
                    rest.auth.authorize { tokenDetails, error in
                        expect(error).to(beNil())
                        authenticatedTokenDetails = tokenDetails
                        done()
                    }
                }
                expect(rest.auth.tokenDetails).to(equal(authenticatedTokenDetails))
            }

            // RSA11d
            it("should be empty if there is no current token") {
                let rest = ARTRest(options: AblyTests.commonAppSetup())
                expect(rest.auth.tokenDetails).to(beNil())
            }

        }
        
        // RSC1 RSC1a RSC1c RSA3d
        describe("JWT and rest") {
            let options = AblyTests.clientOptions()
            
            context("when the JWT token embeds an Ably token") {
                it ("pulls stats successfully") {
                    options.tokenDetails = ARTTokenDetails(token: getJWTToken(jwtType: "embedded")!)
                    let client = ARTRest(options: options)
                    waitUntil(timeout: testTimeout) { done in
                        client.stats { stats, error in
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }
            }
            
            context("when the JWT token embeds an Ably token and it is requested as encrypted") {
                it ("pulls stats successfully") {
                    options.tokenDetails = ARTTokenDetails(token: getJWTToken(jwtType: "embedded", encrypted: 1)!)
                    let client = ARTRest(options: options)
                    waitUntil(timeout: testTimeout) { done in
                        client.stats { stats, error in
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }
            }
            
            // RSA4f, RSA8c
            context("when the JWT token is returned with application/jwt content type") {
                var client: ARTRest!

                func setupDependencies() {
                    if (client == nil) {
                        let options = AblyTests.clientOptions()
                        let keys = getKeys()
                        options.authUrl = URL(string: echoServerAddress)!
                        options.authParams = [URLQueryItem]()
                        options.authParams?.append(URLQueryItem(name: "keyName", value: keys["keyName"]))
                        options.authParams?.append(URLQueryItem(name: "keySecret", value: keys["keySecret"]))
                        options.authParams?.append(URLQueryItem(name: "returnType", value: "jwt"))
                        client = ARTRest(options: options)
                    }
                }

                beforeEach {
                    setupDependencies()
                }
                
                it("the client successfully connects and pulls stats") {
                    waitUntil(timeout: testTimeout) { done in
                        client.stats { stats, error in
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }
                
                it("the client can request a new token to initilize another client that connects and pulls stats") {
                    waitUntil(timeout: testTimeout) { done in
                        client.auth.requestToken(nil, with: nil, callback: { tokenDetails, error in
                            let newClientOptions = AblyTests.clientOptions()
                            newClientOptions.token = tokenDetails!.token
                            let newClient = ARTRest(options: newClientOptions)
                            newClient.stats { stats, error in
                                expect(error).to(beNil())
                                done()
                            }
                        })
                    }
                }
            }

        }

        // https://github.com/ably/ably-cocoa/issues/849
        it("should not force token auth when clientId is set") {
            let options = AblyTests.commonAppSetup()
            options.clientId = "foo"
            expect(options.isBasicAuth()).to(beTrue())
        }

        // https://github.com/ably/ably-cocoa/issues/1093
        it("should accept authURL response with timestamp argument as string") {
            var originalTokenRequest: ARTTokenRequest!
            let tmpRest = ARTRest(options: AblyTests.commonAppSetup())
            waitUntil(timeout: testTimeout) { done in
                let tokenParams = ARTTokenParams()
                tokenParams.clientId = "john"
                tokenParams.capability = """
                {"chat:*":["publish","subscribe","presence","history"]}
                """
                tokenParams.ttl = 43200
                tmpRest.auth.createTokenRequest(tokenParams, options: nil) { tokenRequest, error in
                    expect(error).to(beNil())
                    originalTokenRequest = try! XCTUnwrap(tokenRequest)
                    done()
                }
            }
            // "timestamp" as String
            let tokenRequestJsonString = """
                {"keyName":"\(originalTokenRequest.keyName)","timestamp":"\(String(dateToMilliseconds(originalTokenRequest.timestamp))))","clientId":"\(originalTokenRequest.clientId!)","nonce":"\(originalTokenRequest.nonce)","mac":"\(originalTokenRequest.mac)","ttl":"\(String(originalTokenRequest.ttl!.intValue * 1000)))","capability":"\(originalTokenRequest.capability!.replace("\"", withString: "\\\""))"}
                """

            let options = AblyTests.clientOptions()
            options.authUrl = URL(string: "http://auth-test.ably.cocoa")

            let rest = ARTRest(options: options)
            expect(rest.auth.clientId).to(beNil())
            #if TARGET_OS_IOS
            expect(rest.device.clientId).to(beNil())
            #endif
            let testHttpExecutor = TestProxyHTTPExecutor(options.logHandler)
            rest.internal.httpExecutor = testHttpExecutor
            let channel = rest.channels.get("chat:one")

            testHttpExecutor.simulateIncomingPayloadOnNextRequest(tokenRequestJsonString.data(using: .utf8)!)

            waitUntil(timeout: testTimeout) { done in
                channel.publish("foo", data: nil) { error in
                    expect(error).to(beNil())
                    done()
                }
            }

            expect(testHttpExecutor.requests.at(0)?.url?.host).to(equal("auth-test.ably.cocoa"))
            guard let tokenDetails = rest.internal.auth.tokenDetails else {
                fail("Should have token details"); return
            }
            expect(tokenDetails.clientId).to(equal(originalTokenRequest.clientId))
            expect(tokenDetails.token).toNot(beNil())
        }

    }
}
