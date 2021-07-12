//
//  RestClient.swift
//  ably
//
//  Created by Yavor Georgiev on 2.08.15.
//  Copyright © 2015 г. Ably. All rights reserved.
//

import Ably
import Nimble
import Quick

class RestClient: QuickSpec {
    override func spec() {

        var testHTTPExecutor: TestProxyHTTPExecutor!

        describe("RestClient") {
            // G4
            it("All REST requests should include the current API version") {
                let options = AblyTests.commonAppSetup()
                let client = ARTRest(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                client.internal.httpExecutor = testHTTPExecutor
                let channel = client.channels.get("test")
                waitUntil(timeout: testTimeout) { done in
                    channel.publish(nil, data: "message") { error in
                        expect(error).to(beNil())
                        let version = testHTTPExecutor.requests.first!.allHTTPHeaderFields?["X-Ably-Version"]
                        
                        // This test should not directly validate version against ARTDefault.version(), as
                        // ultimately the version header has been derived from that value.
                        expect(version).to(equal("1.2"))
                        
                        done()
                    }
                }
            }

            // RSC1
            context("initializer") {
                it("should accept an API key") {
                    let options = AblyTests.commonAppSetup()
                    
                    let client = ARTRest(key: options.key!)
                    client.internal.prioritizedHost = options.restHost

                    let publishTask = publishTestMessage(client)

                    expect(publishTask.error).toEventually(beNil(), timeout: testTimeout)
                }

                it("should throw when provided an invalid key") {
                    expect{ ARTRest(key: "invalid_key") }.to(raiseException())
                }

                it("should result in error status when provided a bad key") {
                    let client = ARTRest(key: "fake:key")

                    let publishTask = publishTestMessage(client, failOnError: false)

                    expect(publishTask.error?.code).toEventually(equal(40005), timeout:testTimeout)
                }

                it("should accept a token") {
                    ARTClientOptions.setDefaultEnvironment(getEnvironment())
                    defer { ARTClientOptions.setDefaultEnvironment(nil) }

                    let client = ARTRest(token: getTestToken())
                    let publishTask = publishTestMessage(client)
                    expect(publishTask.error).toEventually(beNil(), timeout: testTimeout)
                }

                it("should accept an options object") {
                    let options = AblyTests.commonAppSetup()
                    let client = ARTRest(options: options)

                    let publishTask = publishTestMessage(client)

                    expect(publishTask.error).toEventually(beNil(), timeout: testTimeout)
                }

                it("should accept an options object with token authentication") {
                    let options = AblyTests.clientOptions(requestToken: true)
                    let client = ARTRest(options: options)

                    let publishTask = publishTestMessage(client)

                    expect(publishTask.error).toEventually(beNil(), timeout: testTimeout)
                }

                it("should result in error status when provided a bad token") {
                    let options = AblyTests.clientOptions()
                    options.token = "invalid_token"
                    let client = ARTRest(options: options)

                    let publishTask = publishTestMessage(client, failOnError: false)

                    expect(publishTask.error?.code).toEventually(equal(40005), timeout: testTimeout)
                }
            }

            context("logging") {
                // RSC2
                it("should output to the system log and the log level should be Warn") {
                    ARTClientOptions.setDefaultEnvironment(getEnvironment())
                    defer {
                        ARTClientOptions.setDefaultEnvironment(nil)
                    }

                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    options.logHandler = ARTLog(capturingOutput: true)
                    let client = ARTRest(options: options)

                    client.internal.logger.log("This is a warning", with: .warn)

                    expect(client.internal.logger.logLevel).to(equal(ARTLogLevel.warn))
                    guard let line = options.logHandler.captured.last else {
                        fail("didn't log line.")
                        return
                    }
                    expect(line.level).to(equal(ARTLogLevel.warn))
                    expect(line.toString()).to(equal("WARN: This is a warning"))
                }

                // RSC3
                it("should have a mutable log level") {
                    let options = AblyTests.commonAppSetup()
                    options.logHandler = ARTLog(capturingOutput: true)
                    let client = ARTRest(options: options)
                    client.internal.logger.logLevel = .error

                    let logTime = NSDate()
                    client.internal.logger.log("This is a warning", with: .warn)

                    let logs = options.logHandler.captured.filter({!$0.date.isBefore(logTime as Date)})
                    expect(logs).to(beEmpty())
                }

                // RSC4
                it("should accept a custom logger") {
                    struct Log {
                        static var interceptedLog: (String, ARTLogLevel) = ("", .none)
                    }
                    class MyLogger : ARTLog {
                        override func log(_ message: String, with level: ARTLogLevel) {
                            Log.interceptedLog = (message, level)
                        }
                    }

                    let options = AblyTests.commonAppSetup()
                    let customLogger = MyLogger()
                    options.logHandler = customLogger
                    options.logLevel = .verbose
                    let client = ARTRest(options: options)

                    client.internal.logger.log("This is a warning", with: .warn)
                    
                    expect(Log.interceptedLog.0).to(equal("This is a warning"))
                    expect(Log.interceptedLog.1).to(equal(ARTLogLevel.warn))
                    
                    expect(client.internal.logger.logLevel).to(equal(customLogger.logLevel))
                }
            }

            // RSC11
            context("endpoint") {
                it("should accept a custom host and send requests to the specified host") {
                    let options = ARTClientOptions(key: "fake:key")
                    options.restHost = "fake.ably.io"
                    let client = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    
                    publishTestMessage(client, failOnError: false)
                    
                    expect(testHTTPExecutor.requests.first?.url?.host).toEventually(equal("fake.ably.io"), timeout: testTimeout)
                }

                it("should ignore an environment when restHost is customized") {
                    let options = ARTClientOptions(key: "fake:key")
                    options.environment = "test"
                    options.restHost = "fake.ably.io"
                    let client = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor

                    publishTestMessage(client, failOnError: false)

                    expect(testHTTPExecutor.requests.first?.url?.host).toEventually(equal("fake.ably.io"), timeout: testTimeout)
                }
                
                it("should accept an environment when restHost is left unchanged") {
                    let options = ARTClientOptions(key: "fake:key")
                    options.environment = "myEnvironment"
                    let client = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    
                    publishTestMessage(client, failOnError: false)
                    
                    expect(testHTTPExecutor.requests.first?.url?.host).toEventually(equal("myEnvironment-rest.ably.io"), timeout: testTimeout)
                }
                
                it("should default to https://rest.ably.io") {
                    let options = ARTClientOptions(key: "fake:key")
                    let client = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    
                    publishTestMessage(client, failOnError: false)
                    
                    expect(testHTTPExecutor.requests.first?.url?.absoluteString).toEventually(beginWith("https://rest.ably.io"), timeout: testTimeout)
                }
                
                it("should connect over plain http:// when tls is off") {
                    let options = AblyTests.clientOptions(requestToken: true)
                    options.tls = false
                    let client = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    
                    publishTestMessage(client, failOnError: false)
                    
                    expect(testHTTPExecutor.requests.first?.url?.scheme).toEventually(equal("http"), timeout: testTimeout)
                }

                it("should not prepend the environment if environment is configured as @production@") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    options.environment = "production"
                    let client = ARTRest(options: options)
                    expect(client.internal.options.restHost).to(equal(ARTDefault.restHost()))
                    expect(client.internal.options.realtimeHost).to(equal(ARTDefault.realtimeHost()))
                }
            }

            // RSC13
            context("should use the the connection and request timeouts specified") {

                it("timeout for any single HTTP request and response") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    options.restHost = "10.255.255.1" //non-routable IP address
                    expect(options.httpRequestTimeout).to(equal(10.0)) //Seconds
                    options.httpRequestTimeout = 1.0
                    let client = ARTRest(options: options)
                    let channel = client.channels.get("test")
                    waitUntil(timeout: testTimeout) { done in
                        let start = NSDate()
                        channel.publish(nil, data: "message") { error in
                            let end = NSDate()
                            expect(end.timeIntervalSince(start as Date)).to(beCloseTo(options.httpRequestTimeout, within: 0.5))
                            expect(error).toNot(beNil())
                            if let error = error {
                                expect((error ).code).to(satisfyAnyOf(equal(-1001 /*Timed Out*/), equal(-1004 /*Cannot Connect To Host*/)))
                            }
                            done()
                        }
                    }
                }

                it("max number of fallback hosts") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    expect(options.httpMaxRetryCount).to(equal(3))
                    options.httpMaxRetryCount = 1
                    let client = ARTRest(options: options)
                    let mockHTTP = MockHTTP(logger: options.logHandler)
                    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    mockHTTP.setNetworkState(network: .hostUnreachable)

                    var totalRetry: UInt = 0
                    testHTTPExecutor.setListenerAfterRequest({ request in
                        if NSRegularExpression.match(request.url!.absoluteString, pattern: "//[a-e].ably-realtime.com") {
                            totalRetry += 1
                        }
                    })

                    let channel = client.channels.get("test")
                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "nil") { _ in
                            done()
                        }
                    }
                    expect(totalRetry).to(equal(options.httpMaxRetryCount))
                }

                it("max elapsed time in which fallback host retries for HTTP requests will be attempted") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    expect(options.httpMaxRetryDuration).to(equal(15.0)) //Seconds
                    options.httpMaxRetryDuration = 1.0
                    let client = ARTRest(options: options)
                    let mockHTTP = MockHTTP(logger: options.logHandler)
                    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    mockHTTP.setNetworkState(network: .requestTimeout(timeout: 0.1))
                    let channel = client.channels.get("test")
                    waitUntil(timeout: testTimeout) { done in
                        let start = Date()
                        channel.publish(nil, data: "nil") { _ in
                            let end = Date()
                            expect(end.timeIntervalSince(start as Date)).to(beCloseTo(options.httpMaxRetryDuration, within: 0.9))
                            done()
                        }
                    }
                }
            }

            // RSC5
            it("should provide access to the AuthOptions object passed in ClientOptions") {
                let options = AblyTests.setupOptions(AblyTests.jsonRestOptions)
                let client = ARTRest(options: options)
                
                let authOptions = client.auth.internal.options

                expect(authOptions == options).to(beTrue())
            }

            // RSC12
            it("REST endpoint host should be configurable in the Client constructor with the option restHost") {
                let options = ARTClientOptions(key: "xxxx:xxxx")
                expect(options.restHost).to(equal("rest.ably.io"))
                options.restHost = "rest.ably.test"
                expect(options.restHost).to(equal("rest.ably.test"))
                let client = ARTRest(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                client.internal.httpExecutor = testHTTPExecutor
                waitUntil(timeout: testTimeout) { done in
                    client.channels.get("test").publish(nil, data: "message") { error in
                        expect(error).toNot(beNil())
                        done()
                    }
                }
                expect(testHTTPExecutor.requests.first!.url!.absoluteString).to(contain("//rest.ably.test"))
            }
            
            // RSC16
            context("time") {
                it("should return server time") {
                    let options = AblyTests.setupOptions(AblyTests.jsonRestOptions)
                    let client = ARTRest(options: options)
                    
                    var time: NSDate?

                    client.time({ date, error in
                        time = date as NSDate? as NSDate?
                    })
                    
                    expect(time?.timeIntervalSince1970).toEventually(beCloseTo(NSDate().timeIntervalSince1970, within: 60), timeout: testTimeout)
                }
            }

            // RSC7, RSC18
            it("should send requests over http and https") {
                let options = AblyTests.commonAppSetup()

                let clientHttps = ARTRest(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                clientHttps.internal.httpExecutor = testHTTPExecutor

                waitUntil(timeout: testTimeout) { done in
                    publishTestMessage(clientHttps) { error in
                        done()
                    }
                }

                let requestUrlA = testHTTPExecutor.requests.first!.url!
                expect(requestUrlA.scheme).to(equal("https"))

                options.clientId = "client_http"
                options.useTokenAuth = true
                options.tls = false
                let clientHttp = ARTRest(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                clientHttp.internal.httpExecutor = testHTTPExecutor

                waitUntil(timeout: testTimeout) { done in
                    publishTestMessage(clientHttp) { error in
                        done()
                    }
                }

                let requestUrlB = testHTTPExecutor.requests.last!.url!
                expect(requestUrlB.scheme).to(equal("http"))
            }

            // RSC9
            it("should use Auth to manage authentication") {
                let options = AblyTests.clientOptions()
                guard let testTokenDetails = getTestTokenDetails() else {
                    fail("No test token details"); return
                }
                options.tokenDetails = testTokenDetails
                options.authCallback = { tokenParams, completion in
                    completion(testTokenDetails, nil)
                }

                let client = ARTRest(options: options)
                expect(client.auth).to(beAnInstanceOf(ARTAuth.self))

                waitUntil(timeout: testTimeout) { done in
                    client.auth.authorize(nil, options: nil) { tokenDetails, error in
                        if let e = error {
                            XCTFail(e.localizedDescription)
                            done()
                            return
                        }
                        guard let tokenDetails = tokenDetails else {
                            XCTFail("expected tokenDetails to not be nil when error is nil")
                            done()
                            return
                        }
                        expect(tokenDetails.token).to(equal(testTokenDetails.token))
                        done()
                    }
                }
            }

            // RSC10
            it("should request another token after current one is no longer valid") {
                let options = AblyTests.commonAppSetup()
                options.token = getTestToken(ttl: 0.5)
                let client = ARTRest(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                client.internal.httpExecutor = testHTTPExecutor
                let auth = client.auth

                waitUntil(timeout: testTimeout) { done in
                    delay(1.0) {
                        client.channels.get("test").history { result, error in
                            expect(error).to(beNil())
                            expect(result).toNot(beNil())

                            guard let headerErrorCode = testHTTPExecutor.responses.first?.value(forHTTPHeaderField: "X-Ably-Errorcode") else {
                                fail("X-Ably-Errorcode not found"); done();
                                return
                            }
                            expect(Int(headerErrorCode)).to(equal(40142))

                            // Different token
                            expect(auth.tokenDetails!.token).toNot(equal(options.token))
                            done()
                        }
                    }
                }
            }

            // RSC10
            it("should result in an error when user does not have sufficient permissions") {
                let options = AblyTests.clientOptions()
                options.token = getTestToken(capability: "{ \"main\":[\"subscribe\"] }")
                let client = ARTRest(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                client.internal.httpExecutor = testHTTPExecutor

                waitUntil(timeout: testTimeout) { done in
                    client.channels.get("test").history { result, error in
                        guard let errorCode = error?.code else {
                            fail("Error is empty"); done();
                            return
                        }
                        expect(errorCode).to(equal(40160))
                        expect(result).to(beNil())

                        guard let headerErrorCode = testHTTPExecutor.responses.first?.value(forHTTPHeaderField: "X-Ably-Errorcode") else {
                            fail("X-Ably-Errorcode not found"); done();
                            return
                        }
                        expect(Int(headerErrorCode)).to(equal(40160))
                        done()
                    }
                }
            }

            // RSC14
            context("Authentication") {

                // RSC14a
                it("should support basic authentication when an API key is provided with the key option") {
                    let options = AblyTests.commonAppSetup()
                    guard let components = options.key?.components(separatedBy: ":"), let keyName = components.first, let keySecret = components.last else {
                        fail("Invalid API key: \(options.key ?? "nil")"); return
                    }
                    ARTClientOptions.setDefaultEnvironment(getEnvironment())
                    defer {
                        ARTClientOptions.setDefaultEnvironment(nil)
                    }
                    let rest = ARTRest(key: "\(keyName):\(keySecret)")
                    waitUntil(timeout: testTimeout) { done in
                        rest.channels.get("foo").publish(nil, data: "testing") { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }

                // RSC14b
                context("basic authentication flag") {
                    it("should be true when key is set") {
                        let client = ARTRest(key: "key:secret")
                        expect(client.auth.internal.options.isBasicAuth()).to(beTrue())
                    }

                    for (caseName, caseSetter) in AblyTests.authTokenCases {
                        it("should be false when \(caseName) is set") {
                            let options = ARTClientOptions()
                            caseSetter(options)

                            let client = ARTRest(options: options)

                            expect(client.auth.internal.options.isBasicAuth()).to(beFalse())
                        }
                    }
                }

                // RSC14c
                it("should error when expired token and no means to renew") {
                    let client = ARTRest(options: AblyTests.commonAppSetup())
                    let auth = client.auth

                    let tokenParams = ARTTokenParams()
                    tokenParams.ttl = 3.0 //Seconds

                    guard let options: ARTClientOptions = (AblyTests.waitFor(timeout: testTimeout) { value in
                        auth.requestToken(tokenParams, with: nil) { tokenDetails, error in
                            if let e = error {
                                XCTFail(e.localizedDescription)
                                value(nil)
                                return
                            }

                            guard let currentTokenDetails = tokenDetails else {
                                XCTFail("expected tokenDetails not to be nil when error is nil")
                                value(nil)
                                return
                            }

                            let options = AblyTests.clientOptions()
                            options.key = client.internal.options.key

                            // Expired token
                            options.tokenDetails = ARTTokenDetails(
                                token: currentTokenDetails.token,
                                expires: currentTokenDetails.expires!.addingTimeInterval(testTimeout.toTimeInterval()),
                                issued: currentTokenDetails.issued,
                                capability: currentTokenDetails.capability,
                                clientId: currentTokenDetails.clientId)

                            options.authUrl = URL(string: "http://test-auth.ably.io")
                            value(options)
                        }
                    }) else {
                        return
                    }

                    let rest = ARTRest(options: options)
                    testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    rest.internal.httpExecutor = testHTTPExecutor

                    waitUntil(timeout: testTimeout) { done in
                        // Delay for token expiration
                        delay(TimeInterval(truncating: tokenParams.ttl!)) {
                            // [40140, 40150) - token expired and will not recover because authUrl is invalid
                            publishTestMessage(rest) { error in
                                guard let errorCode = testHTTPExecutor.responses.first?.value(forHTTPHeaderField: "X-Ably-Errorcode") else {
                                    fail("expected X-Ably-Errorcode header in request")
                                    return
                                }
                                expect(Int(errorCode)).to(beGreaterThanOrEqualTo(40140))
                                expect(Int(errorCode)).to(beLessThan(40150))
                                expect(error).toNot(beNil())
                                done()
                            }
                        }
                    }
                }

                // RSC14d
                it("should renew the token when it has expired") {
                    let client = ARTRest(options: AblyTests.commonAppSetup())
                    let auth = client.auth

                    let tokenParams = ARTTokenParams()
                    tokenParams.ttl = 3.0 //Seconds

                    waitUntil(timeout: testTimeout) { done in
                        auth.requestToken(tokenParams, with: nil) { tokenDetails, error in
                            if let e = error {
                                XCTFail(e.localizedDescription)
                                done()
                                return
                            }

                            guard let currentTokenDetails = tokenDetails else {
                                XCTFail("expected tokenDetails not to be nil when error is nil")
                                done()
                                return
                            }

                            let options = AblyTests.clientOptions()
                            options.key = client.internal.options.key

                            // Expired token
                            options.tokenDetails = ARTTokenDetails(
                                token: currentTokenDetails.token,
                                expires: currentTokenDetails.expires!.addingTimeInterval(testTimeout.toTimeInterval()),
                                issued: currentTokenDetails.issued,
                                capability: currentTokenDetails.capability,
                                clientId: currentTokenDetails.clientId)

                            let rest = ARTRest(options: options)
                            testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                            rest.internal.httpExecutor = testHTTPExecutor

                            // Delay for token expiration
                            delay(TimeInterval(truncating: tokenParams.ttl!)) {
                                // [40140, 40150) - token expired and will not recover because authUrl is invalid
                                publishTestMessage(rest) { error in
                                    guard let errorCode = testHTTPExecutor.responses.first?.value(forHTTPHeaderField: "X-Ably-Errorcode") else {
                                        fail("expected X-Ably-Errorcode header in request")
                                        return
                                    }
                                    expect(Int(errorCode)).to(beGreaterThanOrEqualTo(40140))
                                    expect(Int(errorCode)).to(beLessThan(40150))
                                    expect(error).to(beNil())
                                    expect(rest.auth.tokenDetails!.token).toNot(equal(currentTokenDetails.token))
                                    done()
                                }
                            }
                        }
                    }
                }
            }

            // RSC15
            context("Host Fallback") {

                // TO3k7
                context("fallbackHostsUseDefault option") {

                    it("allows the default fallback hosts to be used when @environment@ is not production") {
                        let options = ARTClientOptions(key: "xxxx:xxxx")
                        options.environment = "not-production"
                        options.fallbackHostsUseDefault = true

                        let client = ARTRest(options: options)
                        expect(client.internal.options.fallbackHostsUseDefault).to(beTrue())
                        // Not production
                        expect(client.internal.options.environment).toNot(beNil())
                        expect(client.internal.options.environment).toNot(equal("production"))

                        let fallback = ARTFallback(options: client.internal.options)
                        expect(fallback.hosts).to(haveCount(ARTDefault.fallbackHosts().count))

                        ARTDefault.fallbackHosts().forEach() {
                            expect(fallback.hosts).to(contain($0))
                        }
                    }

                    it("allows the default fallback hosts to be used when a custom Realtime or REST host endpoint is being used") {
                        let options = ARTClientOptions(key: "xxxx:xxxx")
                        options.restHost = "fake1.ably.io"
                        options.realtimeHost = "fake2.ably.io"
                        options.fallbackHostsUseDefault = true

                        let client = ARTRest(options: options)
                        expect(client.internal.options.fallbackHostsUseDefault).to(beTrue())
                        // Custom
                        expect(client.internal.options.restHost).toNot(equal(ARTDefault.restHost()))
                        expect(client.internal.options.realtimeHost).toNot(equal(ARTDefault.realtimeHost()))

                        let fallback = ARTFallback(options: client.internal.options)
                        expect(fallback.hosts).to(haveCount(ARTDefault.fallbackHosts().count))

                        ARTDefault.fallbackHosts().forEach() {
                            expect(fallback.hosts).to(contain($0))
                        }
                    }

                    it("should be inactive by default") {
                        let options = ARTClientOptions(key: "xxxx:xxxx")
                        expect(options.fallbackHostsUseDefault).to(beFalse())
                    }

                    it("should never accept to configure @fallbackHost@ and set @fallbackHostsUseDefault@ to @true@") {
                        let options = ARTClientOptions(key: "xxxx:xxxx")
                        expect(options.fallbackHosts).to(beNil())
                        expect(options.fallbackHostsUseDefault).to(beFalse())

                        expect{ options.fallbackHosts = [] }.toNot(raiseException())

                        expect{ options.fallbackHostsUseDefault = true }.to(raiseException(named: ARTFallbackIncompatibleOptionsException))

                        options.fallbackHosts = nil

                        expect{ options.fallbackHostsUseDefault = true }.toNot(raiseException())

                        expect { options.fallbackHosts = ["fake.ably.io"] }.to(raiseException(named: ARTFallbackIncompatibleOptionsException))
                    }

                }

                // RSC15b
                it("failing HTTP requests with custom endpoint should result in an error immediately") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    options.environment = "test"
                    let client = ARTRest(options: options)
                    let mockHTTP = MockHTTP(logger: options.logHandler)
                    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    let channel = client.channels.get("test")
                    mockHTTP.setNetworkState(network: .hostUnreachable)

                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "message") { error in
                            expect(error!.message).to(contain("hostname could not be found"))
                            done()
                        }
                    }

                    expect(testHTTPExecutor.requests).to(haveCount(1))
                }

                // RSC15b
                it("applies when the default rest.ably.io endpoint is being used") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    let client = ARTRest(options: options)
                    let mockHTTP = MockHTTP(logger: options.logHandler)
                    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    let channel = client.channels.get("test")
                    mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 1)

                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "nil") { _ in
                            done()
                        }
                    }

                    expect(testHTTPExecutor.requests).to(haveCount(2))
                    if testHTTPExecutor.requests.count < 2 {
                        return
                    }
                    let capturedURLs = testHTTPExecutor.requests.map { $0.url!.absoluteString }
                    expect(NSRegularExpression.match(capturedURLs[0], pattern: "//rest.ably.io")).to(beTrue())
                    expect(NSRegularExpression.match(capturedURLs[1], pattern: "//[a-e].ably-realtime.com")).to(beTrue())
                }
                
                // RSC15b
                it("applies when ClientOptions#fallbackHosts is provided") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    options.fallbackHosts = ["f.ably-realtime.com", "g.ably-realtime.com", "h.ably-realtime.com", "i.ably-realtime.com", "j.ably-realtime.com"]
                    let client = ARTRest(options: options)
                    let mockHTTP = MockHTTP(logger: options.logHandler)
                    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    let channel = client.channels.get("test")
                    mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 1)
                    
                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "nil") { _ in
                            done()
                        }
                    }
                    
                    expect(testHTTPExecutor.requests).to(haveCount(2))
                    if testHTTPExecutor.requests.count < 2 {
                        return
                    }

                    let capturedURLs = testHTTPExecutor.requests.map { $0.url!.absoluteString }
                    expect(NSRegularExpression.match(capturedURLs[1], pattern: "//[f-j].ably-realtime.com")).to(beTrue())
                }

                // RSC15b
                it("applies when ClientOptions#fallbackHostsUseDefault is true") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    options.environment = "rsc15b"
                    options.fallbackHostsUseDefault = true
                    let client = ARTRest(options: options)
                    let mockHTTP = MockHTTP(logger: options.logHandler)
                    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    let channel = client.channels.get("test")
                    mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 1)

                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "nil") { _ in
                            done()
                        }
                    }

                    expect(testHTTPExecutor.requests).to(haveCount(2))
                    if testHTTPExecutor.requests.count < 2 {
                        return
                    }

                    let capturedURLs = testHTTPExecutor.requests.map { $0.url!.absoluteString }
                    expect(NSRegularExpression.match(capturedURLs[1], pattern: "//[a-e].ably-realtime.com")).to(beTrue())
                }

                // RSC15b
                it("do not apply when ClientOptions#fallbackHostsUseDefault is false") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    options.environment = "rsc15b"
                    options.fallbackHostsUseDefault = false
                    let client = ARTRest(options: options)
                    let mockHTTP = MockHTTP(logger: options.logHandler)
                    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    let channel = client.channels.get("test")
                    mockHTTP.setNetworkState(network: .hostUnreachable)

                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "message") { error in
                            expect(error!.message).to(contain("hostname could not be found"))
                            done()
                        }
                    }

                    expect(testHTTPExecutor.requests).to(haveCount(1))
                }
                
                // RSC15b
                it("won't apply fallback hosts if ClientOptions#fallbackHosts array is empty") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    options.fallbackHosts = [] //to test TO3k6
                    let client = ARTRest(options: options)
                    let mockHTTP = MockHTTP(logger: options.logHandler)
                    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    let channel = client.channels.get("test")
                    mockHTTP.setNetworkState(network: .hostUnreachable)
                    
                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "nil") { _ in
                            done()
                        }
                    }
                    
                    expect(testHTTPExecutor.requests).to(haveCount(1))
                    let capturedURLs = testHTTPExecutor.requests.map { $0.url!.absoluteString }
                    expect(NSRegularExpression.match(capturedURLs[0], pattern: "//rest.ably.io")).to(beTrue())
                }
                
                // RSC15b
                it("won't apply custom fallback hosts if ClientOptions#fallbackHosts array is nil, use defaults instead") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    options.fallbackHosts = nil
                    let client = ARTRest(options: options)
                    let mockHTTP = MockHTTP(logger: options.logHandler)
                    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    let channel = client.channels.get("test")
                    mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 1)
                    
                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "nil") { _ in
                            done()
                        }
                    }
                    
                    expect(testHTTPExecutor.requests).to(haveCount(2))
                    if testHTTPExecutor.requests.count < 2 {
                        return
                    }
                    
                    let capturedURLs = testHTTPExecutor.requests.map { $0.url!.absoluteString }
                    expect(NSRegularExpression.match(capturedURLs[1], pattern: "//[a-e].ably-realtime.com")).to(beTrue())
                }

                // RSC15e
                it("every new HTTP request is first attempted to the default primary host rest.ably.io") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    options.httpMaxRetryCount = 1
                    let client = ARTRest(options: options)
                    let mockHTTP = MockHTTP(logger: options.logHandler)
                    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    let channel = client.channels.get("test")
                    mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 1)

                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "nil") { _ in
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "nil") { _ in
                            done()
                        }
                    }

                    expect(testHTTPExecutor.requests).to(haveCount(3))
                    if testHTTPExecutor.requests.count != 3 {
                        return
                    }

                    expect(NSRegularExpression.match(testHTTPExecutor.requests[0].url!.absoluteString, pattern: "//\(ARTDefault.restHost()!)")).to(beTrue())
                    expect(NSRegularExpression.match(testHTTPExecutor.requests[1].url!.absoluteString, pattern: "//[a-e].ably-realtime.com")).to(beTrue())
                    expect(NSRegularExpression.match(testHTTPExecutor.requests[2].url!.absoluteString, pattern: "//\(ARTDefault.restHost()!)")).to(beTrue())
                }

                // RSC15e
                it("if ClientOptions#restHost is set then every new HTTP request should first attempt ClientOptions#restHost") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    options.httpMaxRetryCount = 1
                    options.restHost = "fake.ably.io"
                    let client = ARTRest(options: options)
                    let mockHTTP = MockHTTP(logger: options.logHandler)
                    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    let channel = client.channels.get("test")
                    mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 1)

                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "nil") { _ in
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "nil") { _ in
                            done()
                        }
                    }

                    expect(testHTTPExecutor.requests).to(haveCount(2))
                    if testHTTPExecutor.requests.count != 2 {
                        return
                    }

                    expect(client.internal.options.restHost).to(equal("fake.ably.io"))
                    expect(NSRegularExpression.match(testHTTPExecutor.requests[0].url!.absoluteString, pattern: "//\(client.internal.options.restHost)")).to(beTrue())
                    expect(NSRegularExpression.match(testHTTPExecutor.requests[1].url!.absoluteString, pattern: "//\(client.internal.options.restHost)")).to(beTrue())
                }

                // RSC15a
                context("retry hosts in random order") {
                    let expectedHostOrder = [4, 3, 0, 2, 1]

                    let originalARTFallback_shuffleArray = ARTFallback_shuffleArray

                    beforeEach {
                        ARTFallback_shuffleArray = { array in
                            let arranged = expectedHostOrder.reversed().map { array[$0] }
                            for (i, element) in arranged.enumerated() {
                                array[i] = element
                            }
                        }
                    }

                    afterEach {
                        ARTFallback_shuffleArray = originalARTFallback_shuffleArray
                    }

                    it("default fallback hosts should match @[a-e].ably-realtime.com@") {
                        let defaultFallbackHosts = ARTDefault.fallbackHosts()
                        defaultFallbackHosts?.forEach { host in
                            expect(host).to(match("[a-e].ably-realtime.com"))
                        }
                        expect(defaultFallbackHosts).to(haveCount(5))
                    }

                    it("until httpMaxRetryCount has been reached") {
                        let options = ARTClientOptions(key: "xxxx:xxxx")
                        let client = ARTRest(options: options)
                        options.httpMaxRetryCount = 3
                        let mockHTTP = MockHTTP(logger: options.logHandler)
                        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                        client.internal.httpExecutor = testHTTPExecutor
                        mockHTTP.setNetworkState(network: .hostUnreachable)
                        let channel = client.channels.get("test")

                        waitUntil(timeout: testTimeout) { done in
                            channel.publish(nil, data: "nil") { _ in
                                done()
                            }
                        }

                        expect(testHTTPExecutor.requests).to(haveCount(Int(1 + options.httpMaxRetryCount)))

                        let extractHostname = { (request: URLRequest) in
                            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[a-e].ably-realtime.com")
                        }
                        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
                        let expectedFallbackHosts = Array(expectedHostOrder.map({ ARTDefault.fallbackHosts()[$0] })[0..<Int(options.httpMaxRetryCount)])

                        expect(resultFallbackHosts).to(equal(expectedFallbackHosts))
                    }
                    
                    it("use custom fallback hosts if set") {
                        let options = ARTClientOptions(key: "xxxx:xxxx")
                        options.httpMaxRetryCount = 10
                        let customFallbackHosts = ["j.ably-realtime.com",
                                                   "i.ably-realtime.com",
                                                   "h.ably-realtime.com",
                                                   "g.ably-realtime.com",
                                                   "f.ably-realtime.com"]
                        options.fallbackHosts = customFallbackHosts
                        let client = ARTRest(options: options)
                        let mockHTTP = MockHTTP(logger: options.logHandler)
                        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                        client.internal.httpExecutor = testHTTPExecutor
                        mockHTTP.setNetworkState(network: .hostUnreachable)
                        let channel = client.channels.get("test")
                        
                        waitUntil(timeout: testTimeout) { done in
                            channel.publish(nil, data: "nil") { _ in
                                done()
                            }
                        }

                        expect(testHTTPExecutor.requests).to(haveCount(customFallbackHosts.count + 1))
                        
                        let extractHostname = { (request: URLRequest) in
                            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[f-j].ably-realtime.com")
                        }
                        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
                        let expectedFallbackHosts = expectedHostOrder.map { customFallbackHosts[$0] }
                        
                        expect(resultFallbackHosts).to(equal(expectedFallbackHosts))
                    }

                    it("until all fallback hosts have been tried") {
                        let options = ARTClientOptions(key: "xxxx:xxxx")
                        options.httpMaxRetryCount = 10
                        let client = ARTRest(options: options)
                        let mockHTTP = MockHTTP(logger: options.logHandler)
                        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                        client.internal.httpExecutor = testHTTPExecutor
                        mockHTTP.setNetworkState(network: .hostUnreachable)
                        let channel = client.channels.get("test")

                        waitUntil(timeout: testTimeout) { done in
                            channel.publish(nil, data: "nil") { _ in
                                done()
                            }
                        }

                        expect(testHTTPExecutor.requests).to(haveCount(ARTDefault.fallbackHosts().count + 1))

                        let extractHostname = { (request: URLRequest) in
                            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[a-e].ably-realtime.com")
                        }
                        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
                        let expectedFallbackHosts = expectedHostOrder.map { ARTDefault.fallbackHosts()[$0] }

                        expect(resultFallbackHosts).to(equal(expectedFallbackHosts))
                    }
                    
                    let _fallbackHosts = ["f.ably-realtime.com", "g.ably-realtime.com", "h.ably-realtime.com", "i.ably-realtime.com", "j.ably-realtime.com"]
                    
                    it("until httpMaxRetryCount has been reached, if custom fallback hosts are provided in ClientOptions#fallbackHosts, then they will be used instead") {
                        let options = ARTClientOptions(key: "xxxx:xxxx")
                        options.httpMaxRetryCount = 4
                        options.fallbackHosts = _fallbackHosts
                        
                        let client = ARTRest(options: options)
                        let mockHTTP = MockHTTP(logger: options.logHandler)
                        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                        client.internal.httpExecutor = testHTTPExecutor
                        mockHTTP.setNetworkState(network: .hostUnreachable)
                        let channel = client.channels.get("test")
                        
                        waitUntil(timeout: testTimeout) { done in
                            channel.publish(nil, data: "nil") { _ in
                                done()
                            }
                        }
                        
                        expect(testHTTPExecutor.requests).to(haveCount(Int(1 + options.httpMaxRetryCount)))
                        expect((testHTTPExecutor.requests.count) < (_fallbackHosts.count + 1)).to(beTrue())
                        
                        let extractHostname = { (request: URLRequest) in
                            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[f-j].ably-realtime.com")
                        }
                        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
                        let expectedFallbackHosts = Array(expectedHostOrder.map({ _fallbackHosts[$0] })[0..<Int(options.httpMaxRetryCount)])
                        
                        expect(resultFallbackHosts).to(equal(expectedFallbackHosts))
                    }
                    
                    it("until all fallback hosts have been tried, if custom fallback hosts are provided in ClientOptions#fallbackHosts, then they will be used instead") {
                        let options = ARTClientOptions(key: "xxxx:xxxx")
                        options.httpMaxRetryCount = 10
                        options.fallbackHosts = _fallbackHosts
                        
                        let client = ARTRest(options: options)
                        let mockHTTP = MockHTTP(logger: options.logHandler)
                        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                        client.internal.httpExecutor = testHTTPExecutor
                        mockHTTP.setNetworkState(network: .hostUnreachable)
                        let channel = client.channels.get("test")
                        
                        waitUntil(timeout: testTimeout) { done in
                            channel.publish(nil, data: "nil") { _ in
                                done()
                            }
                        }
                        
                        expect(testHTTPExecutor.requests).to(haveCount(ARTDefault.fallbackHosts().count + 1))
                        
                        let extractHostname = { (request: URLRequest) in
                            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[f-j].ably-realtime.com")
                        }
                        
                        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
                        let expectedFallbackHosts = expectedHostOrder.map { _fallbackHosts[$0] }
                
                        expect(resultFallbackHosts).to(equal(expectedFallbackHosts))
                    }
                    
                    it("all fallback requests headers should contain `Host` header with fallback host address") {
                        let options = ARTClientOptions(key: "xxxx:xxxx")
                        options.httpMaxRetryCount = 10
                        options.fallbackHosts = _fallbackHosts
                        
                        let client = ARTRest(options: options)
                        let mockHTTP = MockHTTP(logger: options.logHandler)
                        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                        client.internal.httpExecutor = testHTTPExecutor
                        mockHTTP.setNetworkState(network: .hostUnreachable)
                        let channel = client.channels.get("test")
                        
                        waitUntil(timeout: testTimeout) { done in
                            channel.publish(nil, data: "nil") { _ in
                                done()
                            }
                        }
                        
                        expect(testHTTPExecutor.requests).to(haveCount(ARTDefault.fallbackHosts().count + 1))
                        
                        let fallbackRequests = testHTTPExecutor.requests.filter {
                            NSRegularExpression.match($0.url!.absoluteString, pattern: "[f-j].ably-realtime.com")
                        }
                        
                        let fallbackRequestsWithHostHeader = fallbackRequests.filter {
                            $0.allHTTPHeaderFields!["Host"] == $0.url?.host
                        }
                                            
                        expect(fallbackRequests.count).to(be(fallbackRequestsWithHostHeader.count))
                    }
                    
                    it("if an empty array of fallback hosts is provided, then fallback host functionality is disabled") {
                        let options = ARTClientOptions(key: "xxxx:xxxx")
                        options.httpMaxRetryCount = 5
                        options.fallbackHosts = []
                        
                        let client = ARTRest(options: options)
                        let mockHTTP = MockHTTP(logger: options.logHandler)
                        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                        client.internal.httpExecutor = testHTTPExecutor
                        mockHTTP.setNetworkState(network: .hostUnreachable)
                        let channel = client.channels.get("test")
                        
                        waitUntil(timeout: testTimeout) { done in
                            channel.publish(nil, data: "nil") { _ in
                                done()
                            }
                        }
                        
                        expect(testHTTPExecutor.requests).to(haveCount(1))
                        expect(NSRegularExpression.match(testHTTPExecutor.requests[0].url!.absoluteString, pattern: "//rest.ably.io")).to(beTrue())
                    }
                }

                // RSC15d
                context("should use an alternative host when") {

                    for caseTest: FakeNetworkResponse in [.hostUnreachable,
                                                          .requestTimeout(timeout: 0.1),
                                                          .hostInternalError(code: 501)] {
                        it("\(caseTest)") {
                            let options = ARTClientOptions(key: "xxxx:xxxx")
                            let client = ARTRest(options: options)
                            let mockHTTP = MockHTTP(logger: options.logHandler)
                            testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                            client.internal.httpExecutor = testHTTPExecutor
                            mockHTTP.setNetworkState(network: caseTest, resetAfter: 1)
                            let channel = client.channels.get("test")

                            waitUntil(timeout: testTimeout) { done in
                                channel.publish(nil, data: "nil") { _ in
                                    done()
                                }
                            }

                            expect(testHTTPExecutor.requests).to(haveCount(2))
                            if testHTTPExecutor.requests.count != 2 {
                                return
                            }
                            expect(NSRegularExpression.match(testHTTPExecutor.requests[0].url!.absoluteString, pattern: "//rest.ably.io")).to(beTrue())
                            expect(NSRegularExpression.match(testHTTPExecutor.requests[1].url!.absoluteString, pattern: "//[a-e].ably-realtime.com")).to(beTrue())
                        }
                    }

                }

                // RSC15d
                it("should not use an alternative host when the client receives an bad request") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    let client = ARTRest(options: options)
                    let mockHTTP = MockHTTP(logger: options.logHandler)
                    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    mockHTTP.setNetworkState(network: .host400BadRequest, resetAfter: 1)
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "nil") { _ in
                            done()
                        }
                    }

                    expect(testHTTPExecutor.requests).to(haveCount(1))
                    expect(NSRegularExpression.match(testHTTPExecutor.requests[0].url!.absoluteString, pattern: "//rest.ably.io")).to(beTrue())
                }
            }

            // RSC8a
            it("should use MsgPack binary protocol") {
                let options = AblyTests.commonAppSetup()
                expect(options.useBinaryProtocol).to(beTrue())

                let rest = ARTRest(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                rest.internal.httpExecutor = testHTTPExecutor
                waitUntil(timeout: testTimeout) { done in
                    rest.channels.get("test").publish(nil, data: "message") { error in
                        done()
                    }
                }

                switch extractBodyAsMsgPack(testHTTPExecutor.requests.first) {
                case .failure(let error):
                    fail(error)
                default: break
                }

                let realtime = AblyTests.newRealtime(options)
                defer { realtime.close() }
                waitUntil(timeout: testTimeout) { done in
                    realtime.channels.get("test").publish(nil, data: "message") { error in
                        done()
                    }
                }

                let transport = realtime.internal.transport as! TestProxyTransport
                let jsonArray = transport.rawDataSent.map({ AblyTests.msgpackToJSON($0) })
                let messageJson = jsonArray.filter({ item in item["action"] == 15 }).last!
                expect(messageJson["messages"][0]["data"].string).to(equal("message"))
            }

            // RSC8b
            it("should use JSON text protocol") {
                let options = AblyTests.commonAppSetup()
                options.useBinaryProtocol = false

                let rest = ARTRest(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                rest.internal.httpExecutor = testHTTPExecutor
                waitUntil(timeout: testTimeout) { done in
                    rest.channels.get("test").publish(nil, data: "message") { error in
                        done()
                    }
                }

                switch extractBodyAsJSON(testHTTPExecutor.requests.first) {
                case .failure(let error):
                    fail(error)
                default: break
                }

                let realtime = AblyTests.newRealtime(options)
                defer { realtime.close() }
                waitUntil(timeout: testTimeout) { done in
                    realtime.channels.get("test").publish(nil, data: "message") { error in
                        done()
                    }
                }

                let transport = realtime.internal.transport as! TestProxyTransport
                let object = try! JSONSerialization.jsonObject(with: transport.rawDataSent.first!, options: JSONSerialization.ReadingOptions(rawValue: 0))
                expect(JSONSerialization.isValidJSONObject(object)).to(beTrue())
            }

            // RSC7a
            it("X-Ably-Version must be included in all REST requests") {
                let options = AblyTests.commonAppSetup()
                let client = ARTRest(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                client.internal.httpExecutor = testHTTPExecutor
                waitUntil(timeout: testTimeout) { done in
                    client.channels.get("test").publish(nil, data: "message") { error in
                        expect(error).to(beNil())
                        guard let headerAblyVersion = testHTTPExecutor.requests.first?.allHTTPHeaderFields?["X-Ably-Version"] else {
                            fail("X-Ably-Version header not found"); done()
                            return
                        }

                        // This test should not directly validate version against ARTDefault.version(), as
                        // ultimately the version header has been derived from that value.
                        expect(headerAblyVersion).to(equal("1.2"))

                        done()
                    }
                }
            }
            
            // RSC7b
            it("X-Ably-Lib: [lib][.optional variant]?-[version] should be included in all REST requests") {
                let options = AblyTests.commonAppSetup()
                let client = ARTRest(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                client.internal.httpExecutor = testHTTPExecutor
                let channel = client.channels.get("test")
                waitUntil(timeout: testTimeout) { done in
                    channel.publish(nil, data: "message") { error in
                        expect(error).to(beNil())
                        let headerLibVersion = testHTTPExecutor.requests.first!.allHTTPHeaderFields?["X-Ably-Lib"]
                        let ablyBundleLibVersion = ARTDefault.libraryVersion()
                        expect(headerLibVersion).to(equal(ablyBundleLibVersion))
                        
                        let patternToMatch = "cocoa\(ARTDefault_variant)-1.2."
                        let match = headerLibVersion?.hasPrefix(patternToMatch)
                        expect(match).to(beTrue())
                        
                        done()
                    }
                }
            }

            // https://github.com/ably/ably-cocoa/issues/117
            it("should indicate an error if there is no way to renew the token") {
                let options = AblyTests.clientOptions()
                options.token = getTestToken(ttl: 0.1)
                let client = ARTRest(options: options)
                waitUntil(timeout: testTimeout) { done in
                    delay(0.1) {
                        client.channels.get("test").publish(nil, data: "message") { error in
                            guard let error = error else {
                                fail("Error is empty"); done()
                                return
                            }
                            expect((error ).code).to(equal(Int(ARTState.requestTokenFailed.rawValue)))
                            expect(error.message).to(contain("no means to renew the token is provided"))
                            done()
                        }
                    }
                }
            }

            // https://github.com/ably/ably-cocoa/issues/577
            it("background behaviour") {
                let options = AblyTests.commonAppSetup()
                waitUntil(timeout: testTimeout) { done in
                  URLSession.shared.dataTask(with: URL(string:"https://ably.io")!) { _ , _ , _  in
                        let rest = ARTRest(options: options)
                    rest.channels.get("foo").history { _ , _  in
                            done()
                        }
                    }.resume()
                }
            }

            // https://github.com/ably/ably-cocoa/issues/589
            it("client should handle error messages in plaintext and HTML format") {
                let request = URLRequest(url: URL(string: "https://www.example.com")!)
                waitUntil(timeout: testTimeout) { done in
                    let rest = ARTRest(key: "xxxx:xxxx")
                    rest.internal.execute(request, completion: { response, data, error in
                        guard let contentType = response?.allHeaderFields["Content-Type"] as? String else {
                            fail("Response should have a Content-Type"); done(); return
                        }
                        expect(contentType).to(contain("text/html"))
                        guard let error = error as? ARTErrorInfo else {
                            fail("Error is nil"); done(); return
                        }
                        expect(error.statusCode) == 200
                        expect(error.message.lengthOfBytes(using: String.Encoding.utf8)) == 1000
                        done()
                    })
                }
            }

            // RSC19
            context("request") {

                // RSC19a
                context("method signature and arguments") {
                    it("should add query parameters") {
                        let rest = ARTRest(key: "xxxx:xxxx")
                        let mockHttpExecutor = MockHTTPExecutor()
                        rest.internal.httpExecutor = mockHttpExecutor
                        let params = ["foo": "1"]

                        waitUntil(timeout: testTimeout) { done in
                            do {
                                try rest.request("patch", path: "feature", params: params, body: nil, headers: nil) { paginatedResult, error in
                                    expect(error).to(beNil())
                                    expect(paginatedResult).toNot(beNil())
                                    done()
                                }
                            }
                            catch {
                                fail(error.localizedDescription)
                                done()
                            }
                        }

                        guard let request = mockHttpExecutor.requests.first else {
                            fail("No requests found")
                            return
                        }

                        guard let url = request.url, url.absoluteString == "https://rest.ably.io:443/feature?foo=1" else {
                            fail("should have a \"/feature\" URL with query \(params)"); return
                        }
                        expect(request.httpMethod) == "patch"

                        guard let acceptHeaderValue = request.allHTTPHeaderFields?["Accept"] else {
                            fail("Accept HTTP Header is missing"); return
                        }
                        expect(acceptHeaderValue).to(equal("application/x-msgpack,application/json"))
                    }

                    it("should add a HTTP body") {
                        let rest = ARTRest(key: "xxxx:xxxx")
                        let mockHttpExecutor = MockHTTPExecutor()
                        rest.internal.httpExecutor = mockHttpExecutor
                        let bodyDict = ["blockchain": true]

                        waitUntil(timeout: testTimeout) { done in
                            do {
                                try rest.request("post", path: "feature", params: nil, body: bodyDict, headers: nil) { paginatedResult, error in
                                    expect(error).to(beNil())
                                    expect(paginatedResult).toNot(beNil())
                                    done()
                                }
                            }
                            catch {
                                fail(error.localizedDescription)
                                done()
                            }
                        }

                        guard let request = mockHttpExecutor.requests.first else {
                            fail("No requests found")
                            return
                        }
                        guard let rawBody = request.httpBody else {
                            fail("should have a body"); return
                        }

                        let decodedBody: Any
                        do {
                            decodedBody = try rest.internal.defaultEncoder.decode(rawBody)
                        }
                        catch {
                            fail("decode failure: \(error)"); return
                        }

                        guard let body = decodedBody as? NSDictionary else {
                            fail("body is invalid"); return
                        }
                        expect(body.value(forKey: "blockchain") as? Bool).to(beTrue())
                    }

                    it("should add a HTTP header") {
                        let rest = ARTRest(key: "xxxx:xxxx")
                        let mockHttpExecutor = MockHTTPExecutor()
                        rest.internal.httpExecutor = mockHttpExecutor
                        let headers = ["X-foo": "ok"]

                        waitUntil(timeout: testTimeout) { done in
                            do {
                                try rest.request("get", path: "feature", params: nil, body: nil, headers: headers) { paginatedResult, error in
                                    expect(error).to(beNil())
                                    expect(paginatedResult).toNot(beNil())
                                    done()
                                }
                            }
                            catch {
                                fail(error.localizedDescription)
                                done()
                            }
                        }

                        guard let request = mockHttpExecutor.requests.first else {
                            fail("No requests found")
                            return
                        }

                        let authorization = request.allHTTPHeaderFields?["X-foo"]
                        expect(authorization).to(equal("ok"))
                    }

                    it("should error if method is invalid") {
                        let rest = ARTRest(key: "xxxx:xxxx")
                        let mockHTTPExecutor = MockHTTPExecutor()
                        rest.internal.httpExecutor = mockHTTPExecutor

                        do {
                            try rest.request("A", path: "feature", params: nil, body: nil, headers: nil) { paginatedResult, error in
                                fail("Completion closure should not be called")
                            }
                        }
                        catch let error as NSError {
                            expect(error.code).to(equal(ARTCustomRequestError.invalidMethod.rawValue))
                            expect(error.localizedDescription).to(contain("Method isn't valid"))
                        }

                        do {
                            try rest.request("", path: "feature", params: nil, body: nil, headers: nil) { paginatedResult, error in
                                fail("Completion closure should not be called")
                            }
                        }
                        catch let error as NSError {
                            expect(error.code).to(equal(ARTCustomRequestError.invalidMethod.rawValue))
                            expect(error.localizedDescription).to(contain("Method isn't valid"))
                        }
                    }

                    it("should error if path is invalid") {
                        let rest = ARTRest(key: "xxxx:xxxx")
                        let mockHTTPExecutor = MockHTTPExecutor()
                        rest.internal.httpExecutor = mockHTTPExecutor

                        do {
                            try rest.request("get", path: "new feature", params: nil, body: nil, headers: nil) { paginatedResult, error in
                                fail("Completion closure should not be called")
                            }
                        }
                        catch let error as NSError {
                            expect(error.code).to(equal(ARTCustomRequestError.invalidPath.rawValue))
                            expect(error.localizedDescription).to(contain("Path isn't valid"))
                        }

                        do {
                            try rest.request("get", path: "", params: nil, body: nil, headers: nil) { paginatedResult, error in
                                fail("Completion closure should not be called")
                            }
                        }
                        catch let error as NSError {
                            expect(error.code).to(equal(ARTCustomRequestError.invalidPath.rawValue))
                            expect(error.localizedDescription).to(contain("Path cannot be empty"))
                        }
                    }

                    it("should error if body is not a Dictionary or an Array") {
                        let rest = ARTRest(key: "xxxx:xxxx")
                        let mockHttpExecutor = MockHTTPExecutor()
                        rest.internal.httpExecutor = mockHttpExecutor

                        do {
                            try rest.request("get", path: "feature", params: nil, body: mockHttpExecutor, headers: nil) { paginatedResult, error in
                                fail("Completion closure should not be called")
                            }
                        }
                        catch let error as NSError {
                            expect(error.code).to(equal(ARTCustomRequestError.invalidBody.rawValue))
                            expect(error.localizedDescription).to(contain("should be a Dictionary or an Array"))
                        }
                    }

                    it("should do a request and receive a valid response") {
                        let options = AblyTests.commonAppSetup()
                        let rest = ARTRest(options: options)
                        let channel = rest.channels.get("request-method-test")
                        waitUntil(timeout: testTimeout) { done in
                            channel.publish("a", data: nil) { error in
                                expect(error).to(beNil())
                                done()
                            }
                        }

                        let proxyHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                        rest.internal.httpExecutor = proxyHTTPExecutor

                        var httpPaginatedResponse: ARTHTTPPaginatedResponse!
                        waitUntil(timeout: testTimeout) { done in
                            do {
                                try rest.request("get", path: "/channels/\(channel.name)", params: nil, body: nil, headers: nil) { paginatedResponse, error in
                                    expect(error).to(beNil())
                                    guard let paginatedResponse = paginatedResponse else {
                                        fail("PaginatedResult is empty"); done(); return
                                    }
                                    expect(paginatedResponse.items.count) == 1
                                    guard let channelDetailsDict = paginatedResponse.items.first else {
                                        fail("PaginatedResult first element is missing"); done(); return
                                    }
                                    expect(channelDetailsDict.value(forKey: "channelId") as? String).to(equal(channel.name))
                                    expect(paginatedResponse.hasNext) == false
                                    expect(paginatedResponse.isLast) == true
                                    expect(paginatedResponse.statusCode) == 200
                                    expect(paginatedResponse.success) == true
                                    expect(paginatedResponse.errorCode) == 0
                                    expect(paginatedResponse.errorMessage).to(beNil())
                                    expect(paginatedResponse.headers).toNot(beEmpty())
                                    httpPaginatedResponse = paginatedResponse
                                    done()
                                }
                            }
                            catch {
                                fail(error.localizedDescription)
                                done()
                            }
                        }

                        guard let response = proxyHTTPExecutor.responses.first else {
                            fail("No responses found")
                            return
                        }

                        expect(response.statusCode) == httpPaginatedResponse.statusCode
                        expect(response.allHeaderFields as NSDictionary) == httpPaginatedResponse.headers
                    }

                    it("should handle response failures") {
                        let options = AblyTests.commonAppSetup()
                        let rest = ARTRest(options: options)
                        let channel = rest.channels.get("request-method-test")
                        waitUntil(timeout: testTimeout) { done in
                            channel.publish("a", data: nil) { error in
                                expect(error).to(beNil())
                                done()
                            }
                        }

                        let proxyHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                        rest.internal.httpExecutor = proxyHTTPExecutor

                        waitUntil(timeout: testTimeout) { done in
                            do {
                                try rest.request("get", path: "feature", params: nil, body: nil, headers: nil) { paginatedResponse, error in
                                    expect(error).to(beNil())
                                    guard let paginatedResponse = paginatedResponse else {
                                        fail("PaginatedResult is empty"); done(); return
                                    }
                                    expect(paginatedResponse.items.count) == 0
                                    expect(paginatedResponse.hasNext) == false
                                    expect(paginatedResponse.isLast) == true
                                    expect(paginatedResponse.statusCode) == 404
                                    expect(paginatedResponse.success) == false
                                    expect(paginatedResponse.errorCode) == 40400
                                    expect(paginatedResponse.errorMessage).to(contain("Could not find path"))
                                    expect(paginatedResponse.headers).toNot(beEmpty())
                                    expect(paginatedResponse.headers["X-Ably-Errorcode"] as? String).to(equal("40400"))
                                    done()
                                }
                            }
                            catch {
                                fail(error.localizedDescription)
                                done()
                            }
                        }

                        guard let response = proxyHTTPExecutor.responses.first else {
                            fail("No responses found")
                            return
                        }

                        expect(response.statusCode) == 404
                        expect(response.value(forHTTPHeaderField: "X-Ably-Errorcode")).to(equal("40400"))
                    }
                }

            }

            context("if in the course of a REST request an attempt to authenticate using authUrl fails due to a timeout") {
                // RSA4e
                it("the request should result in an error with code 40170, statusCode 401, and a suitable error message") {
                    let options = AblyTests.commonAppSetup()
                    let token = getTestToken()
                    options.httpRequestTimeout = 3 // short timeout to make it fail faster
                    options.authUrl = URL(string: "http://10.255.255.1")!
                    options.authParams = [URLQueryItem]()
                    options.authParams?.append(URLQueryItem(name: "type", value: "text"))
                    options.authParams?.append(URLQueryItem(name: "body", value: token))

                    let client = ARTRest(options: options)
                    waitUntil(timeout: testTimeout) { done in
                        let channel = client.channels.get("test-channel")
                        channel.publish("test", data: "test-data") { error in
                            guard let error = error else {
                                fail("Error should not be empty")
                                done()
                                return
                            }
                            expect(error.statusCode).to(equal(401))
                            expect(error.code).to(equal(40170))
                            expect(error.message).to(contain("Error in requesting auth token"))
                            done()
                        }
                    }
                }
            }

            // RSC7c
            context("request IDs") {

                it("should add 'request_id' query parameter") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    options.addRequestIds = true

                    let restA = ARTRest(options: options)
                    let mockHttpExecutor = MockHTTPExecutor()
                    restA.internal.httpExecutor = mockHttpExecutor
                    waitUntil(timeout: testTimeout) { done in
                        restA.channels.get("foo").publish(nil, data: "something") { error in
                            expect(error).to(beNil())
                            guard let url = mockHttpExecutor.requests.first?.url else {
                                fail("No requests found")
                                return
                            }
                            expect(url.query).to(contain("request_id"))
                            done()
                        }
                    }

                    mockHttpExecutor.reset()

                    options.addRequestIds = false
                    let restB = ARTRest(options: options)
                    restB.internal.httpExecutor = mockHttpExecutor
                    waitUntil(timeout: testTimeout) { done in
                        restB.channels.get("foo").publish(nil, data: "something") { error in
                            expect(error).to(beNil())
                            expect(mockHttpExecutor.requests).to(haveCount(1))
                            guard let url = mockHttpExecutor.requests.first?.url else {
                                fail("No requests found")
                                return
                            }
                            expect(url.query).to(beNil())
                            done()
                        }
                    }
                }

                it("should remain the same if a request is retried to a fallback host") {
                    let options = ARTClientOptions(key: "xxxx:xxxx")
                    options.httpMaxRetryCount = 5
                    options.addRequestIds = true
                    options.logLevel = .debug

                    let client = ARTRest(options: options)
                    let mockHTTP = MockHTTP(logger: options.logHandler)
                    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: options.logHandler)
                    client.internal.httpExecutor = testHTTPExecutor
                    mockHTTP.setNetworkState(network: .hostUnreachable)

                    var fallbackRequests: [URLRequest] = []
                    testHTTPExecutor.setListenerAfterRequest({ request in
                        if NSRegularExpression.match(request.url!.absoluteString, pattern: "//[a-e].ably-realtime.com") {
                            fallbackRequests += [request]
                        }
                    })

                    var requestId: String = ""
                    let channel = client.channels.get("test")
                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "something") { error in
                            guard let error = error else {
                                fail("Expecting an error"); done(); return
                            }
                            guard let firstRequestId = extractURLQueryValue(testHTTPExecutor.requests.first?.url, key: "request_id") else {
                                fail("First request attempt doesn't have the 'request_id'."); return
                            }
                            requestId = firstRequestId
                            expect(error.message).to(contain(requestId))
                            done()
                        }
                    }

                    expect(fallbackRequests).toNot(beEmpty())
                    expect(fallbackRequests).to(allPass { extractURLQueryValue($0?.url, key: "request_id") == requestId })
                }

            }

        } // RestClient
    }
}
