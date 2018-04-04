//
//  PushActivationStateMachine.swift
//  Ably
//
//  Created by Ricardo Pereira on 18/04/2017.
//  Copyright © 2017 Ably. All rights reserved.
//

import Ably
import Nimble
import Quick

class PushActivationStateMachine : QuickSpec {
    override func spec() {

        var rest: ARTRest!
        var httpExecutor: MockHTTPExecutor!
        var storage: MockDeviceStorage!
        var initialStateMachine: ARTPushActivationStateMachine!

        beforeEach {
            rest = ARTRest(key: "xxxx:xxxx")
            httpExecutor = MockHTTPExecutor()
            rest.httpExecutor = httpExecutor
            storage = MockDeviceStorage()
            rest.storage = storage
            initialStateMachine = ARTPushActivationStateMachine(rest)
        }

        describe("Activation state machine") {

            it("should set NotActivated state as current state when disk is empty") {
                expect(initialStateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
            }

            it("should read the current state from disk") {
                let storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForDeviceRegistration(machine: initialStateMachine))
                rest.storage = storage
                let stateMachine = ARTPushActivationStateMachine(rest)
                expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeviceRegistration.self))
                expect(storage.keysRead).to(haveCount(2))
                expect(storage.keysRead.filter({ $0.hasSuffix("CurrentState") })).to(haveCount(1))
                expect(storage.keysWritten).to(beEmpty())
            }

            // RSH3a
            context("State NotActivated") {

                var stateMachine: ARTPushActivationStateMachine!
                var storage: MockDeviceStorage!

                beforeEach {
                    storage = MockDeviceStorage(startWith: ARTPushActivationStateNotActivated(machine: initialStateMachine))
                    rest.storage = storage
                    stateMachine = ARTPushActivationStateMachine(rest)
                }

                it("on Event CalledDeactivate, should transition to NotActivated") {
                    var deactivatedCallbackCalled = false
                    let hook = stateMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("callDeactivatedCallback:")) {
                        deactivatedCallbackCalled = true
                    }
                    defer { hook.remove() }

                    stateMachine.send(ARTPushActivationEventCalledDeactivate())

                    expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
                    expect(deactivatedCallbackCalled).to(beTrue())
                }

                context("on Event CalledActivate") {
                    it("if the local device has id and deviceIdentityToken then should transition to WaitingForNewPushDeviceDetails") {
                        let testDeviceId = "aaaa"
                        storage.simulateOnNextRead(string: testDeviceId, for: ARTDeviceIdKey)

                        let testDeviceIdentityTokenDetails = ARTDeviceIdentityTokenDetails(token: "xxxx-xxxx-xxx", issued: Date(), expires: Date.distantFuture, capability: "", deviceId: testDeviceId)
                        stateMachine.rest.device.setAndPersistIdentityTokenDetails(testDeviceIdentityTokenDetails)
                        defer { stateMachine.rest.device.setAndPersistIdentityTokenDetails(nil) }

                        stateMachine.send(ARTPushActivationEventCalledActivate())
                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))
                    }

                    it("if the local device has the necessary push details should send event GotPushDeviceDetails") {
                        let delegate = StateMachineDelegate()
                        stateMachine.delegate = delegate

                        let testDeviceToken = "xxxx-xxxx-xxxx-xxxx-xxxx"
                        stateMachine.rest.device.setAndPersistDeviceToken(testDeviceToken)
                        defer { stateMachine.rest.device.setAndPersistDeviceToken(nil) }

                        waitUntil(timeout: testTimeout) { done in
                            let partialDone = AblyTests.splitDone(2, done: done)
                            stateMachine.transitions = { event, from, to in
                                if event is ARTPushActivationEventCalledActivate {
                                    partialDone()
                                }
                                if event is ARTPushActivationEventGotPushDeviceDetails {
                                    partialDone()
                                }
                            }
                            stateMachine.send(ARTPushActivationEventCalledActivate())
                        }
                    }

                    it("none of them then should transition to WaitingForPushDeviceDetails") {
                        stateMachine.send(ARTPushActivationEventCalledActivate())
                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))
                    }

                    it("on Event GotPushDeviceDetails") {
                        stateMachine.send(ARTPushActivationEventGotPushDeviceDetails())
                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
                    }
                }

            }

            // RSH3b
            context("State WaitingForPushDeviceDetails") {

                var stateMachine: ARTPushActivationStateMachine!
                var storage: MockDeviceStorage!

                beforeEach {
                    storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForPushDeviceDetails(machine: initialStateMachine))
                    rest.storage = storage
                    stateMachine = ARTPushActivationStateMachine(rest)
                }

                it("on Event CalledActivate") {
                    stateMachine.send(ARTPushActivationEventCalledActivate())
                    expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))
                }

                it("on Event CalledDeactivate") {
                    var deactivatedCallbackCalled = false
                    let hook = stateMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("callDeactivatedCallback:")) {
                        deactivatedCallbackCalled = true
                    }
                    defer { hook.remove() }

                    stateMachine.send(ARTPushActivationEventCalledDeactivate())
                    expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
                    expect(deactivatedCallbackCalled).to(beTrue())
                }

                // RSH3b3
                context("on Event GotPushDeviceDetails") {

                    // TODO: The exception is raised but the `send:` method is doing an async call and the `expect` doesn't catch it
                    pending("should raise exception if ARTPushRegistererDelegate is not implemented") {
                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))
                        expect {
                            stateMachine.send(ARTPushActivationEventGotPushDeviceDetails())
                        }.to(raiseException { exception in
                            expect(exception.reason).to(contain("ARTPushRegistererDelegate must be implemented"))
                        })
                    }

                    it("should use custom registerCallback and fire GotDeviceRegistration event") {
                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))

                        let delegate = StateMachineDelegateCustomCallbacks()
                        stateMachine.delegate = delegate

                        waitUntil(timeout: testTimeout) { done in
                            let partialDone = AblyTests.splitDone(2, done: done)
                            stateMachine.transitions = { event, from, to in
                                if event is ARTPushActivationEventGotDeviceRegistration {
                                    stateMachine.transitions = nil
                                    partialDone()
                                }
                            }
                            delegate.onPushCustomRegister = { error, deviceDetails in
                                expect(error).to(beNil())
                                expect(deviceDetails).to(beIdenticalTo(rest.device))
                                partialDone()
                                return nil
                            }
                            stateMachine.send(ARTPushActivationEventGotPushDeviceDetails())
                            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeviceRegistration.self))
                        }

                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))
                        expect(httpExecutor.requests.count) == 0
                    }

                    it("should use custom registerCallback and fire GettingDeviceRegistrationFailed event") {
                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))

                        let delegate = StateMachineDelegateCustomCallbacks()
                        stateMachine.delegate = delegate

                        waitUntil(timeout: testTimeout) { done in
                            let simulatedError = NSError(domain: "", code: 1234, userInfo: nil)
                            let partialDone = AblyTests.splitDone(2, done: done)
                            stateMachine.transitions = { event, from, to in
                                if let event = event as? ARTPushActivationEventGettingDeviceRegistrationFailed {
                                    expect(event.error.domain) == ARTAblyErrorDomain
                                    expect(event.error.code) == simulatedError.code
                                    stateMachine.transitions = nil
                                    partialDone()
                                }
                            }
                            delegate.onPushCustomRegister = { error, deviceDetails in
                                expect(error).to(beNil())
                                expect(deviceDetails).to(beIdenticalTo(rest.device))
                                partialDone()
                                return simulatedError
                            }
                            stateMachine.send(ARTPushActivationEventGotPushDeviceDetails())
                            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeviceRegistration.self))
                        }

                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
                        expect(httpExecutor.requests.count) == 0
                    }

                    it("should fire GotDeviceRegistration event") {
                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))

                        let delegate = StateMachineDelegate()
                        stateMachine.delegate = delegate

                        var setAndPersistIdentityTokenDetailsCalled = false
                        let hookDevice = stateMachine.rest.device.testSuite_injectIntoMethod(after: NSSelectorFromString("setAndPersistIdentityTokenDetails:")) {
                            setAndPersistIdentityTokenDetailsCalled = true
                        }
                        defer { hookDevice.remove() }

                        waitUntil(timeout: testTimeout) { done in
                            stateMachine.transitions = { event, from, to in
                                if event is ARTPushActivationEventGotDeviceRegistration {
                                    stateMachine.transitions = nil
                                    done()
                                }
                            }
                            stateMachine.send(ARTPushActivationEventGotPushDeviceDetails())
                            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeviceRegistration.self))
                        }

                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))
                        expect(setAndPersistIdentityTokenDetailsCalled).to(beTrue())
                        expect(httpExecutor.requests.count) == 1
                        let requests = httpExecutor.requests.flatMap({ $0.url?.path }).filter({ $0 == "/push/deviceRegistrations" })
                        expect(requests).to(haveCount(1))
                        guard let request = httpExecutor.requests.first else {
                            fail("should have a \"/push/deviceRegistrations\" request"); return
                        }
                        guard let url = request.url else {
                            fail("should have a \"/push/deviceRegistrations\" URL"); return
                        }
                        guard let rawBody = request.httpBody else {
                            fail("should have a body"); return
                        }
                        guard let body = stateMachine.rest.defaultEncoder.decode(rawBody, error: nil) as? NSDictionary else {
                            fail("body is invalid"); return
                        }
                        expect(request.httpMethod) == "POST"
                        expect(body.value(forKey: "id") as? String).to(equal(rest.device.id))
                        expect(body.value(forKey: "push")).toNot(beNil())
                        expect(body.value(forKey: "formFactor")).toNot(beNil())
                        expect(body.value(forKey: "platform")).toNot(beNil())
                    }

                    it("should fire GettingDeviceRegistrationFailed event") {
                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))

                        let delegate = StateMachineDelegate()
                        stateMachine.delegate = delegate

                        let simulatedError = NSError(domain: "", code: 1234, userInfo: nil)
                        httpExecutor.simulateIncomingErrorOnNextRequest(simulatedError)

                        waitUntil(timeout: testTimeout) { done in
                            stateMachine.transitions = { event, from, to in
                                if let event = event as? ARTPushActivationEventGettingDeviceRegistrationFailed {
                                    expect(event.error.domain) == ARTAblyErrorDomain
                                    expect(event.error.code) == simulatedError.code
                                    stateMachine.transitions = nil
                                    done()
                                }
                            }
                            stateMachine.send(ARTPushActivationEventGotPushDeviceDetails())
                            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeviceRegistration.self))
                        }

                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
                        expect(httpExecutor.requests.count) == 1
                        let requests = httpExecutor.requests.flatMap({ $0.url?.path }).filter({ $0 == "/push/deviceRegistrations" })
                        expect(requests).to(haveCount(1))
                        guard let request = httpExecutor.requests.first else {
                            fail("should have a \"/push/deviceRegistrations\" request"); return
                        }
                        guard let url = request.url else {
                            fail("should have a \"/push/deviceRegistrations\" URL"); return
                        }
                        guard let rawBody = request.httpBody else {
                            fail("should have a body"); return
                        }
                        guard let body = stateMachine.rest.defaultEncoder.decode(rawBody, error: nil) as? NSDictionary else {
                            fail("body is invalid"); return
                        }
                        expect(body.value(forKey: "id") as? String).to(equal(rest.device.id))
                        expect(body.value(forKey: "push")).toNot(beNil())
                        expect(body.value(forKey: "formFactor")).toNot(beNil())
                        expect(body.value(forKey: "platform")).toNot(beNil())
                    }

                }

            }

            // RSH3c
            context("State WaitingForDeviceRegistration") {

                var stateMachine: ARTPushActivationStateMachine!
                var storage: MockDeviceStorage!

                beforeEach {
                    storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForDeviceRegistration(machine: initialStateMachine))
                    rest.storage = storage
                    stateMachine = ARTPushActivationStateMachine(rest)
                }

                it("on Event CalledActivate") {
                    stateMachine.send(ARTPushActivationEventCalledActivate())
                    expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeviceRegistration.self))
                }

                it("on Event GotDeviceRegistration") {
                    var activatedCallbackCalled = false
                    let hook = stateMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("callActivatedCallback:")) {
                        activatedCallbackCalled = true
                    }
                    defer { hook.remove() }

                    stateMachine.send(ARTPushActivationEventGotDeviceRegistration())
                    expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))
                    expect(activatedCallbackCalled).to(beTrue())
                }

                it("on Event GettingDeviceRegistrationFailed") {
                    var activatedCallbackCalled = false
                    let hook = stateMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("callActivatedCallback:")) {
                        activatedCallbackCalled = true
                    }
                    defer { hook.remove() }

                    stateMachine.send(ARTPushActivationEventGettingDeviceRegistrationFailed())
                    expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
                    expect(activatedCallbackCalled).to(beTrue())
                }

            }

            // RSH3d
            context("State WaitingForNewPushDeviceDetails") {

                var stateMachine: ARTPushActivationStateMachine!
                var storage: MockDeviceStorage!

                beforeEach {
                    storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForNewPushDeviceDetails(machine: initialStateMachine))
                    rest.storage = storage
                    stateMachine = ARTPushActivationStateMachine(rest)
                }

                it("on Event CalledActivate") {
                    var activatedCallbackCalled = false
                    let hook = stateMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("callActivatedCallback:")) {
                        activatedCallbackCalled = true
                    }
                    defer { hook.remove() }

                    stateMachine.send(ARTPushActivationEventCalledActivate())
                    expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))
                    expect(activatedCallbackCalled).to(beTrue())
                }

                // RSH3d2
                context("on Event CalledDeactivate") {

                    it("should use custom deregisterCallback and fire Deregistered event") {
                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))

                        let delegate = StateMachineDelegateCustomCallbacks()
                        stateMachine.delegate = delegate

                        waitUntil(timeout: testTimeout) { done in
                            let partialDone = AblyTests.splitDone(2, done: done)
                            stateMachine.transitions = { event, from, to in
                                if event is ARTPushActivationEventDeregistered {
                                    stateMachine.transitions = nil
                                    partialDone()
                                }
                            }
                            delegate.onPushCustomDeregister = { error, deviceId in
                                expect(error).to(beNil())
                                expect(deviceId) == rest.device.id
                                partialDone()
                                return nil
                            }
                            stateMachine.send(ARTPushActivationEventCalledDeactivate())
                            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                        }

                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
                        expect(httpExecutor.requests.count) == 0
                    }

                    it("should use custom deregisterCallback and fire DeregistrationFailed event") {
                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))

                        let delegate = StateMachineDelegateCustomCallbacks()
                        stateMachine.delegate = delegate

                        waitUntil(timeout: testTimeout) { done in
                            let simulatedError = NSError(domain: "", code: 1234, userInfo: nil)
                            let partialDone = AblyTests.splitDone(2, done: done)
                            stateMachine.transitions = { event, from, to in
                                if let event = event as? ARTPushActivationEventDeregistrationFailed {
                                    expect(event.error.domain) == ARTAblyErrorDomain
                                    expect(event.error.code) == simulatedError.code
                                    stateMachine.transitions = nil
                                    partialDone()
                                }
                            }
                            delegate.onPushCustomDeregister = { error, deviceId in
                                expect(error).to(beNil())
                                expect(deviceId) == rest.device.id
                                partialDone()
                                return simulatedError
                            }
                            stateMachine.send(ARTPushActivationEventCalledDeactivate())
                            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                        }

                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                        expect(httpExecutor.requests.count) == 0
                    }

                    it("should fire Deregistered event and include DeviceSecret HTTP header") {
                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))

                        let delegate = StateMachineDelegate()
                        stateMachine.delegate = delegate

                        waitUntil(timeout: testTimeout) { done in
                            stateMachine.transitions = { event, from, to in
                                if event is ARTPushActivationEventDeregistered {
                                    stateMachine.transitions = nil
                                    done()
                                }
                            }
                            stateMachine.send(ARTPushActivationEventCalledDeactivate())
                            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                        }

                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
                        expect(httpExecutor.requests.count) == 1
                        let requests = httpExecutor.requests.flatMap({ $0.url?.path }).filter({ $0 == "/push/deviceRegistrations" })
                        expect(requests).to(haveCount(1))
                        guard let request = httpExecutor.requests.first else {
                            fail("should have a \"/push/deviceRegistrations\" request"); return
                        }
                        guard let url = request.url else {
                            fail("should have a \"/push/deviceRegistrations\" URL"); return
                        }
                        expect(request.httpMethod) == "DELETE"
                        expect(url.query).to(contain(rest.device.id))
                        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]
                        expect(authorization).to(equal(rest.device.secret))
                    }

                    it("should fire Deregistered event and include DeviceIdentityToken HTTP header") {
                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))

                        let delegate = StateMachineDelegate()
                        stateMachine.delegate = delegate

                        let testIdentityTokenDetails = ARTDeviceIdentityTokenDetails(
                            token: "123456",
                            issued: Date(),
                            expires: Date.distantFuture,
                            capability: "",
                            deviceId: rest.device.id
                        )

                        expect(rest.device.identityTokenDetails).to(beNil())
                        rest.device.setAndPersistIdentityTokenDetails(testIdentityTokenDetails)
                        defer { rest.device.setAndPersistIdentityTokenDetails(nil) }
                        expect(rest.device.identityTokenDetails).toNot(beNil())

                        waitUntil(timeout: testTimeout) { done in
                            stateMachine.transitions = { event, from, to in
                                if event is ARTPushActivationEventDeregistered {
                                    stateMachine.transitions = nil
                                    done()
                                }
                            }
                            stateMachine.send(ARTPushActivationEventCalledDeactivate())
                            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                        }

                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
                        expect(httpExecutor.requests.count) == 1
                        let requests = httpExecutor.requests.flatMap({ $0.url?.path }).filter({ $0 == "/push/deviceRegistrations" })
                        expect(requests).to(haveCount(1))
                        guard let request = httpExecutor.requests.first else {
                            fail("should have a \"/push/deviceRegistrations\" request"); return
                        }
                        guard let url = request.url else {
                            fail("should have a \"/push/deviceRegistrations\" URL"); return
                        }
                        expect(request.httpMethod) == "DELETE"
                        expect(url.query).to(contain(rest.device.id))
                        expect(rest.device.identityTokenDetails).to(beNil())
                        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceIdentityToken"]
                        expect(authorization).to(equal(testIdentityTokenDetails.token.base64Encoded()))
                    }

                    it("should fire DeregistrationFailed event") {
                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))

                        let delegate = StateMachineDelegate()
                        stateMachine.delegate = delegate

                        let simulatedError = NSError(domain: "", code: 1234, userInfo: nil)
                        httpExecutor.simulateIncomingErrorOnNextRequest(simulatedError)

                        waitUntil(timeout: testTimeout) { done in
                            stateMachine.transitions = { event, from, to in
                                if let event = event as? ARTPushActivationEventDeregistrationFailed {
                                    expect(event.error.domain) == ARTAblyErrorDomain
                                    expect(event.error.code) == simulatedError.code
                                    stateMachine.transitions = nil
                                    done()
                                }
                            }
                            stateMachine.send(ARTPushActivationEventCalledDeactivate())
                            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                        }

                        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                        expect(httpExecutor.requests.count) == 1
                        let requests = httpExecutor.requests.flatMap({ $0.url?.path }).filter({ $0 == "/push/deviceRegistrations" })
                        expect(requests).to(haveCount(1))
                        guard let request = httpExecutor.requests.first else {
                            fail("should have a \"/push/deviceRegistrations\" request"); return
                        }
                        guard let url = request.url else {
                            fail("should have a \"/push/deviceRegistrations\" URL"); return
                        }
                        expect(request.httpMethod) == "DELETE"
                        expect(url.query).to(contain(rest.device.id))
                    }

                }

            }

            context("State WaitingForRegistrationUpdate") {
                // Doesn't happen in iOS
            }

            context("State AfterRegistrationUpdateFailed") {

                it("on Event CalledActivate") {
                    // Doesn't happen in iOS
                }

                it("on Event GotPushDeviceDetails") {
                    // Doesn't happen in iOS
                }

                it("on Event CalledDeactivate") {
                    // Doesn't happen in iOS
                }

            }

            // RSH3g
            context("State WaitingForDeregistration") {

                var stateMachine: ARTPushActivationStateMachine!
                var storage: MockDeviceStorage!

                beforeEach {
                    storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForDeregistration(machine: initialStateMachine))
                    rest.storage = storage
                    stateMachine = ARTPushActivationStateMachine(rest)
                }

                it("on Event CalledDeactivate") {
                    stateMachine.send(ARTPushActivationEventCalledDeactivate())
                    expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                }

                it("on Event Deregistered") {
                    var deactivatedCallbackCalled = false
                    let hook = stateMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("callDeactivatedCallback:")) {
                        deactivatedCallbackCalled = true
                    }
                    defer { hook.remove() }

                    var setAndPersistIdentityTokenDetailsCalled = false
                    let hookDevice = stateMachine.rest.device.testSuite_injectIntoMethod(after: NSSelectorFromString("setAndPersistIdentityTokenDetails:")) {
                        setAndPersistIdentityTokenDetailsCalled = true
                    }
                    defer { hookDevice.remove() }

                    stateMachine.send(ARTPushActivationEventDeregistered())
                    expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
                    expect(deactivatedCallbackCalled).to(beTrue())
                    expect(setAndPersistIdentityTokenDetailsCalled).to(beTrue())
                }

                it("on Event DeregistrationFailed") {
                    var deactivatedCallbackCalled = false
                    let hook = stateMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("callDeactivatedCallback:")) {
                        deactivatedCallbackCalled = true
                    }
                    defer { hook.remove() }

                    stateMachine.send(ARTPushActivationEventDeregistrationFailed())
                    expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                    expect(deactivatedCallbackCalled).to(beTrue())
                }

            }

        }
    }
}

class StateMachineDelegate: NSObject, ARTPushRegistererDelegate {

    var onDidActivateAblyPush: ((ARTErrorInfo?) -> Void)?
    var onDidDeactivateAblyPush: ((ARTErrorInfo?) -> Void)?
    var onDidAblyPushRegistrationFail: ((ARTErrorInfo?) -> Void)?

    func didActivateAblyPush(_ error: ARTErrorInfo?) {
        onDidActivateAblyPush?(error)
    }

    func didDeactivateAblyPush(_ error: ARTErrorInfo?) {
        onDidDeactivateAblyPush?(error)
    }

    func didAblyPushRegistrationFail(_ error: ARTErrorInfo?) {
        onDidAblyPushRegistrationFail?(error)
    }

}

typealias ARTDeviceId = String

class StateMachineDelegateCustomCallbacks: StateMachineDelegate {

    var onPushCustomRegister: ((ARTErrorInfo?, ARTDeviceDetails?) -> NSError?)?
    var onPushCustomDeregister: ((ARTErrorInfo?, ARTDeviceId?) -> NSError?)?

    func ablyPushCustomRegister(_ error: ARTErrorInfo?, deviceDetails: ARTDeviceDetails?, callback: @escaping (ARTDeviceIdentityTokenDetails?, ARTErrorInfo?) -> Void) {
        let error = onPushCustomRegister?(error, deviceDetails)
        delay(0) { [deviceId = deviceDetails?.id] in
            let deviceIdentityTokenDetails = ARTDeviceIdentityTokenDetails(token: "123456", issued: Date(), expires: Date.distantFuture, capability: "", deviceId: deviceId ?? "unknown")
            callback(deviceIdentityTokenDetails, error == nil ? nil : ARTErrorInfo.create(from: error!))
        }
    }

    func ablyPushCustomDeregister(_ error: ARTErrorInfo?, deviceId: String?, callback: ((ARTErrorInfo?) -> Void)? = nil) {
        let error = onPushCustomDeregister?(error, deviceId)
        delay(0) {
            callback?(error == nil ? nil : ARTErrorInfo.create(from: error!))
        }
    }

}
