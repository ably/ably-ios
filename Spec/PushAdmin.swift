//
//  PushAdmin.swift
//  Ably
//
//  Created by Ricardo Pereira on 25/10/2017.
//  Copyright © 2017 Ably. All rights reserved.
//

import Ably
import Nimble
import Quick

class PushAdmin : QuickSpec {

    private static var deviceDetails: ARTDeviceDetails = {
        let deviceDetails = ARTDeviceDetails(id: "testDeviceDetails")
        deviceDetails.platform = "ios"
        deviceDetails.formFactor = "phone"
        deviceDetails.metadata = NSMutableDictionary()
        deviceDetails.push.recipient = [
            "transportType": "apns",
            "deviceToken": "foo"
        ]
        return deviceDetails
    }()

    private static var deviceDetails1ClientA: ARTDeviceDetails = {
        let deviceDetails = ARTDeviceDetails(id: "deviceDetails1ClientA")
        deviceDetails.platform = "android"
        deviceDetails.formFactor = "tablet"
        deviceDetails.clientId = "clientA"
        deviceDetails.metadata = NSMutableDictionary()
        deviceDetails.push.recipient = [
            "transportType": "gcm",
            "registrationToken": "qux"
        ]
        return deviceDetails
    }()

    private static var deviceDetails2ClientA: ARTDeviceDetails = {
        let deviceDetails = ARTDeviceDetails(id: "deviceDetails2ClientA")
        deviceDetails.platform = "android"
        deviceDetails.formFactor = "tablet"
        deviceDetails.clientId = "clientA"
        deviceDetails.metadata = NSMutableDictionary()
        deviceDetails.push.recipient = [
            "transportType": "gcm",
            "registrationToken": "qux"
        ]
        return deviceDetails
    }()

    private static var deviceDetails3ClientB: ARTDeviceDetails = {
        let deviceDetails = ARTDeviceDetails(id: "deviceDetails3ClientB")
        deviceDetails.platform = "android"
        deviceDetails.formFactor = "tablet"
        deviceDetails.clientId = "clientB"
        deviceDetails.metadata = NSMutableDictionary()
        deviceDetails.push.recipient = [
            "transportType": "gcm",
            "registrationToken": "qux"
        ]
        return deviceDetails
    }()

    private static var allDeviceDetails: [ARTDeviceDetails] = [
        deviceDetails,
        deviceDetails1ClientA,
        deviceDetails2ClientA,
        deviceDetails3ClientB,
    ]

    private static var subscriptionFooDevice1 = ARTPushChannelSubscription(deviceId: "deviceDetails1ClientA", channel: "pushenabled:foo")
    private static var subscriptionFooDevice2 = ARTPushChannelSubscription(deviceId: "deviceDetails2ClientA", channel: "pushenabled:foo")
    private static var subscriptionBarDevice2 = ARTPushChannelSubscription(deviceId: "deviceDetails2ClientA", channel: "pushenabled:bar")
    private static var subscriptionFooClientA = ARTPushChannelSubscription(clientId: "clientA", channel: "pushenabled:foo")
    private static var subscriptionFooClientB = ARTPushChannelSubscription(clientId: "clientB", channel: "pushenabled:foo")
    private static var subscriptionBarClientB = ARTPushChannelSubscription(clientId: "clientB", channel: "pushenabled:bar")

    private static var allSubscriptions: [ARTPushChannelSubscription] = [
        subscriptionFooDevice1,
        subscriptionFooDevice2,
        subscriptionBarDevice2,
        subscriptionFooClientA,
        subscriptionFooClientB,
        subscriptionBarClientB,
    ]

    private lazy var deviceDetails: ARTDeviceDetails = PushAdmin.deviceDetails
    private lazy var deviceDetails1ClientA: ARTDeviceDetails = PushAdmin.deviceDetails1ClientA
    private lazy var deviceDetails2ClientA: ARTDeviceDetails = PushAdmin.deviceDetails2ClientA
    private lazy var deviceDetails3ClientB: ARTDeviceDetails = PushAdmin.deviceDetails3ClientB

    private lazy var allDeviceDetails: [ARTDeviceDetails] = PushAdmin.allDeviceDetails

    private lazy var subscriptionFooDevice1: ARTPushChannelSubscription = PushAdmin.subscriptionFooDevice1
    private lazy var subscriptionFooDevice2: ARTPushChannelSubscription = PushAdmin.subscriptionFooDevice2
    private lazy var subscriptionBarDevice2: ARTPushChannelSubscription = PushAdmin.subscriptionBarDevice2
    private lazy var subscriptionFooClientA: ARTPushChannelSubscription = PushAdmin.subscriptionFooClientA
    private lazy var subscriptionFooClientB: ARTPushChannelSubscription = PushAdmin.subscriptionFooClientB
    private lazy var subscriptionBarClientB: ARTPushChannelSubscription = PushAdmin.subscriptionBarClientB

    private lazy var allSubscriptions: [ARTPushChannelSubscription] = PushAdmin.allSubscriptions

    private lazy var allSubscriptionsChannels: [String] = {
        var seen = Set<String>()
        return allSubscriptions.filter({ seen.insert($0.channel).inserted }).map({ $0.channel })
    }()

    override class func setUp() {
        super.setUp()
        let options = AblyTests.commonAppSetup()
        options.pushFullWait = true
        options.dispatchQueue = AblyTests.userQueue
        let rest = ARTRest(options: options)
        rest.internal.storage = MockDeviceStorage()
        let group = DispatchGroup()

        group.enter()
        for device in allDeviceDetails {
            rest.push.admin.deviceRegistrations.save(device) { error in
                assert(error == nil, error?.message ?? "no message")
                if (allDeviceDetails.last == device) {
                    group.leave()
                }
            }
        }
        group.wait()

        group.enter()
        for subscription in allSubscriptions {
            rest.push.admin.channelSubscriptions.save(subscription) { error in
                assert(error == nil, error?.message ?? "no message")
                if (allSubscriptions.last == subscription) {
                    group.leave()
                }
            }
        }

        group.wait()
    }

    override class func tearDown() {
        let options = AblyTests.commonAppSetup()
        options.dispatchQueue = AblyTests.userQueue
        let rest = ARTRest(options: options)
        rest.internal.storage = MockDeviceStorage()
        let group = DispatchGroup()

        for device in allDeviceDetails {
            group.enter()
            rest.push.admin.deviceRegistrations.remove(device.id) { _ in
                group.leave()
            }
        }

        for subscription in allSubscriptions {
            group.enter()
            rest.push.admin.channelSubscriptions.remove(subscription) { _ in
                group.leave()
            }
        }

        super.tearDown()
    }

    override func spec() {

        var rest: ARTRest!
        var mockHttpExecutor: MockHTTPExecutor!
        var storage: MockDeviceStorage!
        var localDevice: ARTLocalDevice!

        let recipient = [
            "clientId": "bob"
        ]

        let payload = [
            "notification": [
                "title": "Welcome"
            ]
        ]

        beforeEach {
            rest = ARTRest(key: "xxxx:xxxx")
            mockHttpExecutor = MockHTTPExecutor()
            rest.internal.httpExecutor = mockHttpExecutor
            storage = MockDeviceStorage()
            rest.internal.storage = storage
            localDevice = rest.device
        }
        
        let quxChannelName = "pushenabled:qux"

        // RSH1a
        describe("publish") {

            it("should perform an HTTP request to /push/publish") {
                waitUntil(timeout: testTimeout) { done in
                    rest.push.admin.publish(recipient, data: payload) { error in
                        expect(error).to(beNil())
                        done()
                    }
                }

                guard let request = mockHttpExecutor.requests.first else {
                    fail("Request is missing"); return
                }
                guard let url = request.url else {
                    fail("URL is missing"); return
                }

                expect(url.absoluteString).to(contain("/push/publish"))

                switch extractBodyAsMsgPack(request) {
                case .failure(let error):
                    XCTFail(error)
                case .success(let httpBody):
                    guard let bodyRecipient = httpBody.unbox["recipient"] as? [String: String]  else {
                        fail("recipient is missing"); return
                    }
                    expect(bodyRecipient).to(equal(recipient))

                    guard let bodyPayload = httpBody.unbox["notification"] as? [String: String] else {
                        fail("notification is missing"); return
                    }
                    expect(bodyPayload).to(equal(payload["notification"]))
                }
            }

            xit("should publish successfully") {
                let options = AblyTests.commonAppSetup()
                let realtime = ARTRealtime(options: options)
                defer { realtime.dispose(); realtime.close() }
                let channel = realtime.channels.get("pushenabled:push_admin_publish-ok")
                let publishObject = ["transportType": "ablyChannel",
                                     "channel": channel.name,
                                     "ablyKey": options.key!,
                                     "ablyUrl": "https://\(options.restHost)"]

                waitUntil(timeout: testTimeout) { done in
                    channel.attach() { error in
                        expect(error).to(beNil())
                        done()
                    }
                }

                waitUntil(timeout: testTimeout) { done in
                    let partialDone = AblyTests.splitDone(2, done: done)
                    channel.subscribe("__ably_push__") { message in
                        guard let data = message.data as? String else {
                            fail("Failure in reading returned data"); partialDone(); return
                        }
                        expect(data).to(contain("foo"))
                        partialDone()
                    }
                    realtime.push.admin.publish(publishObject, data: ["data": ["foo": "bar"]]) { error in
                        expect(error).to(beNil())
                        partialDone()
                    }
                }
            }

            xit("should fail with a bad recipient") {
                let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                defer { realtime.dispose(); realtime.close() }
                let channel = realtime.channels.get("pushenabled:push_admin_publish-bad-recipient")

                waitUntil(timeout: testTimeout) { done in
                    channel.attach() { error in
                        expect(error).to(beNil())
                        done()
                    }
                }

                waitUntil(timeout: testTimeout) { done in
                    channel.subscribe("__ably_push__") { message in
                        fail("Should not be called")
                    }
                    realtime.push.admin.publish(["foo": "bar"], data: ["data": ["foo": "bar"]]) { error in
                        guard let error = error else {
                            fail("Error is missing"); done(); return
                        }
                        expect(error.statusCode) == 400
                        expect(error.message).to(contain("recipient must contain"))
                        done()
                    }
                }
            }

            xit("should fail with an empty recipient") {
                let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                defer { realtime.dispose(); realtime.close() }
                let channel = realtime.channels.get("pushenabled:push_admin_publish-empty-recipient")

                waitUntil(timeout: testTimeout) { done in
                    channel.attach() { error in
                        expect(error).to(beNil())
                        done()
                    }
                }

                waitUntil(timeout: testTimeout) { done in
                    channel.subscribe("__ably_push__") { message in
                        fail("Should not be called")
                    }
                    realtime.push.admin.publish([:], data: ["data": ["foo": "bar"]]) { error in
                        guard let error = error else {
                            fail("Error is missing"); done(); return
                        }
                        expect(error.message.lowercased()).to(contain("recipient is missing"))
                        done()
                    }
                }
            }

            it("should fail with an empty payload") {
                let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                defer { realtime.dispose(); realtime.close() }
                let channel = realtime.channels.get("pushenabled:push_admin_publish-empty-payload")

                waitUntil(timeout: testTimeout) { done in
                    channel.attach() { error in
                        expect(error).to(beNil())
                        done()
                    }
                }

                waitUntil(timeout: testTimeout) { done in
                    channel.subscribe("__ably_push__") { message in
                        fail("Should not be called")
                    }
                    realtime.push.admin.publish(["ablyChannel": channel.name], data: [:]) { error in
                        guard let error = error else {
                            fail("Error is missing"); done(); return
                        }
                        expect(error.message.lowercased()).to(contain("data payload is missing"))
                        done()
                    }
                }
            }

        }

        describe("Device Registrations") {

            // RSH1b1
            context("get") {
                it("should return a device") {
                    let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { realtime.dispose(); realtime.close() }
                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.deviceRegistrations.get("testDeviceDetails") { device, error in
                            guard let device = device else {
                                fail("Device is missing"); done(); return;
                            }
                            expect(device).to(equal(self.deviceDetails))
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }

                it("should not return a device if it doesnt exist") {
                    let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { realtime.dispose(); realtime.close() }
                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.deviceRegistrations.get("madeup") { device, error in
                            expect(device).to(beNil())
                            guard let error = error else {
                                fail("Error should not be empty"); done(); return
                            }
                            expect(error.statusCode) == 404
                            expect(error.message).to(contain("not found"))
                            done()
                        }
                    }
                }

                context("push device authentication") {
                    it("should include DeviceIdentityToken HTTP header") {
                        let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { realtime.dispose(); realtime.close() }
                        realtime.internal.rest.httpExecutor = mockHttpExecutor

                        let testIdentityTokenDetails = ARTDeviceIdentityTokenDetails(
                            token: "123456",
                            issued: Date(),
                            expires: Date.distantFuture,
                            capability: "",
                            clientId: ""
                        )

                        expect(localDevice.identityTokenDetails).to(beNil())
                        realtime.internal.rest.device.setAndPersistIdentityTokenDetails(testIdentityTokenDetails)
                        defer { realtime.internal.rest.device.setAndPersistIdentityTokenDetails(nil) }

                        waitUntil(timeout: testTimeout) { done in
                            realtime.push.admin.deviceRegistrations.get(localDevice.id) { device, error in
                                done()
                            }
                        }

                        guard let request = mockHttpExecutor.requests.first else {
                            fail("No requests found")
                            return
                        }

                        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceToken"]
                        expect(authorization).to(equal(testIdentityTokenDetails.token.base64Encoded()))
                    }

                    it("should include DeviceSecret HTTP header") {
                        let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { realtime.dispose(); realtime.close() }
                        realtime.internal.rest.httpExecutor = mockHttpExecutor

                        waitUntil(timeout: testTimeout) { done in
                            realtime.push.admin.deviceRegistrations.get(localDevice.id) { device, error in
                                done()
                            }
                        }

                        guard let request = mockHttpExecutor.requests.first else {
                            fail("No requests found")
                            return
                        }

                        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]
                        expect(authorization).to(equal(localDevice.secret))
                    }
                }
            }

            // RSH1b2
            context("list") {
                it("should list devices by id") {
                    let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { realtime.dispose(); realtime.close() }
                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.deviceRegistrations.list(["deviceId": "testDeviceDetails"]) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be empty"); done(); return
                            }
                            expect(result.items.count) == 1
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }

                it("should list devices by client id") { [allDeviceDetails] in
                    let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { realtime.dispose(); realtime.close() }
                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.deviceRegistrations.list(["clientId": "clientA"]) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be empty"); done(); return
                            }
                            expect(result.items.count) == allDeviceDetails.filter({ $0.clientId == "clientA" }).count
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }

                it("should list devices sorted") { [allDeviceDetails] in
                    let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { realtime.dispose(); realtime.close() }
                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.deviceRegistrations.list(["direction": "forwards"]) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be empty"); done(); return
                            }
                            expect(result.items.count) == allDeviceDetails.count
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }

                it("should return an empty list when id does not exist") {
                    let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { realtime.dispose(); realtime.close() }
                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.deviceRegistrations.list(["deviceId": "madeup"]) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be empty"); done(); return
                            }
                            expect(result.items.count) == 0
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }
            }

            // RSH1b4
            context("remove") {
                it("should unregister a device") {
                    let options = AblyTests.commonAppSetup()
                    options.pushFullWait = true
                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }
                    realtime.internal.rest.httpExecutor = mockHttpExecutor
                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.deviceRegistrations.remove(self.deviceDetails.id) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    guard let request = mockHttpExecutor.requests.first else {
                        fail("No requests found")
                        return
                    }

                    expect(request.httpMethod) == "DELETE"
                    expect(request.allHTTPHeaderFields?["X-Ably-DeviceToken"]).to(beNil())
                    expect(request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]).to(beNil())
                }
            }

            // RSH1b3
            context("save") {
                it("should register a device") {
                    let options = AblyTests.commonAppSetup()
                    options.pushFullWait = true
                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }
                    realtime.internal.rest.httpExecutor = mockHttpExecutor
                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.deviceRegistrations.save(self.deviceDetails) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    guard let request = mockHttpExecutor.requests.first else {
                        fail("No requests found")
                        return
                    }

                    expect(request.httpMethod) == "PUT"
                    expect(request.allHTTPHeaderFields?["X-Ably-DeviceToken"]).to(beNil())
                    expect(request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]).to(beNil())
                }

                context("push device authentication") {
                    it("should include DeviceIdentityToken HTTP header") {
                        let options = AblyTests.commonAppSetup()
                        options.pushFullWait = true
                        let realtime = ARTRealtime(options: options)
                        defer { realtime.dispose(); realtime.close() }
                        realtime.internal.rest.httpExecutor = mockHttpExecutor

                        let testIdentityTokenDetails = ARTDeviceIdentityTokenDetails(
                            token: "123456",
                            issued: Date(),
                            expires: Date.distantFuture,
                            capability: "",
                            clientId: ""
                        )

                        expect(localDevice.identityTokenDetails).to(beNil())
                        realtime.internal.rest.device.setAndPersistIdentityTokenDetails(testIdentityTokenDetails)
                        defer { realtime.internal.rest.device.setAndPersistIdentityTokenDetails(nil) }

                        waitUntil(timeout: testTimeout) { done in
                            realtime.push.admin.deviceRegistrations.save(localDevice) { error in
                                expect(error).to(beNil())
                                done()
                            }
                        }

                        guard let request = mockHttpExecutor.requests.first else {
                            fail("No requests found")
                            return
                        }
                        expect(request.httpMethod).to(equal("PUT"))

                        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceToken"]
                        expect(authorization).to(equal(testIdentityTokenDetails.token.base64Encoded()))
                    }

                    it("should include DeviceSecret HTTP header") {
                        let options = AblyTests.commonAppSetup()
                        options.pushFullWait = true
                        let realtime = ARTRealtime(options: options)
                        defer { realtime.dispose(); realtime.close() }
                        realtime.internal.rest.httpExecutor = mockHttpExecutor

                        waitUntil(timeout: testTimeout) { done in
                            realtime.push.admin.deviceRegistrations.save(localDevice) { error in
                                expect(error).to(beNil())
                                done()
                            }
                        }

                        guard let request = mockHttpExecutor.requests.first else {
                            fail("No requests found")
                            return
                        }
                        expect(request.httpMethod).to(equal("PUT"))

                        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]
                        expect(authorization).to(equal(localDevice.secret))
                    }
                }
            }

            // RSH1b5
            context("removeWhere") { [allDeviceDetails] in
                it("should unregister a device") {
                    let options = AblyTests.commonAppSetup()
                    options.pushFullWait = true
                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }

                    let params = [
                        "clientId": "clientA"
                    ]

                    let expectedRemoved = allDeviceDetails.filter({ $0.clientId == "clientA" })

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.deviceRegistrations.list(params) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be nil"); done(); return
                            }
                            expect(result.items).to(contain(expectedRemoved))
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    realtime.internal.rest.httpExecutor = mockHttpExecutor

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.deviceRegistrations.removeWhere(params) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    guard let request = mockHttpExecutor.requests.first else {
                        fail("No requests found")
                        return
                    }

                    expect(request.httpMethod) == "DELETE"
                    expect(request.allHTTPHeaderFields?["X-Ably-DeviceToken"]).to(beNil())
                    expect(request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]).to(beNil())

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.deviceRegistrations.list(params) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be nil"); done(); return
                            }
                            expect(result.items.count) == 0
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    // --- Restore state for next tests ---

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(expectedRemoved.count, done: done)
                        for removedDevice in expectedRemoved {
                            realtime.push.admin.deviceRegistrations.save(removedDevice) { error in
                                expect(error).to(beNil())
                                partialDone()
                            }
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        realtime.push.admin.channelSubscriptions.save(self.subscriptionFooDevice2) { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                        realtime.push.admin.channelSubscriptions.save(self.subscriptionBarDevice2) { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                    }
                }
            }

        }

        describe("Channel Subscriptions") {

            let subscription = ARTPushChannelSubscription(clientId: "newClient", channel: quxChannelName)

            // RSH1c3
            context("save") {
                it("should add a subscription") {
                    let options = AblyTests.commonAppSetup()
                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }
                    let testProxyHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    realtime.internal.rest.httpExecutor = testProxyHTTPExecutor

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.save(subscription) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    guard let request = testProxyHTTPExecutor.requests.first else {
                        fail("No requests found")
                        return
                    }

                    expect(request.httpMethod).to(equal("POST"))
                    expect(request.allHTTPHeaderFields?["X-Ably-DeviceToken"]).to(beNil())
                    expect(request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]).to(beNil())
                }

                it("should update a subscription") {
                    let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { realtime.dispose(); realtime.close() }
                    let updateSubscription = ARTPushChannelSubscription(clientId: subscription.clientId!, channel: "pushenabled:foo")
                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.save(updateSubscription) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }

                it("should fail with a bad recipient") {
                    let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { realtime.dispose(); realtime.close() }
                    let invalidSubscription = ARTPushChannelSubscription(deviceId: "madeup", channel: "pushenabled:foo")
                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.save(invalidSubscription) { error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error.statusCode) == 400
                            expect(error.message).to(contain("device madeup doesn't exist"))
                            done()
                        }
                    }
                }

                context("push device authentication") {
                    it("should include DeviceIdentityToken HTTP header") {
                        let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { realtime.dispose(); realtime.close() }
                        realtime.internal.rest.httpExecutor = mockHttpExecutor

                        let testIdentityTokenDetails = ARTDeviceIdentityTokenDetails(
                            token: "123456",
                            issued: Date(),
                            expires: Date.distantFuture,
                            capability: "",
                            clientId: ""
                        )

                        expect(localDevice.identityTokenDetails).to(beNil())
                        realtime.internal.rest.device.setAndPersistIdentityTokenDetails(testIdentityTokenDetails)
                        defer { realtime.internal.rest.device.setAndPersistIdentityTokenDetails(nil) }

                        let subscription = ARTPushChannelSubscription(deviceId: localDevice.id, channel: quxChannelName)

                        waitUntil(timeout: testTimeout) { done in
                            realtime.push.admin.channelSubscriptions.save(subscription) { error in
                                expect(error).to(beNil())
                                done()
                            }
                        }

                        guard let request = mockHttpExecutor.requests.first else {
                            fail("No requests found")
                            return
                        }

                        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceToken"]
                        expect(authorization).to(equal(testIdentityTokenDetails.token.base64Encoded()))
                    }

                    it("should include DeviceSecret HTTP header") {
                        let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { realtime.dispose(); realtime.close() }
                        realtime.internal.rest.httpExecutor = mockHttpExecutor

                        let subscription = ARTPushChannelSubscription(deviceId: localDevice.id, channel: quxChannelName)

                        waitUntil(timeout: testTimeout) { done in
                            realtime.push.admin.channelSubscriptions.save(subscription) { error in
                                expect(error).to(beNil())
                                done()
                            }
                        }

                        guard let request = mockHttpExecutor.requests.first else {
                            fail("No requests found")
                            return
                        }

                        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]
                        expect(authorization).to(equal(localDevice.secret))
                    }
                }
            }

            // RSH1c1
            context("list") {
                it("should receive a list of subscriptions") {
                    let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { realtime.dispose(); realtime.close() }
                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.save(subscription) { error in
                            expect(error).to(beNil())
                            realtime.push.admin.channelSubscriptions.list(["channel": quxChannelName]) { result, error in
                                guard let result = result else {
                                    fail("PaginatedResult should not be empty"); done(); return
                                }
                                expect(result.items.count) == 1
                                expect(error).to(beNil())
                                done()
                            }
                        }
                    }
                }
            }

            // RSH1c2
            context("listChannels") { [allSubscriptionsChannels] in
                it("should receive a list of subscriptions") {
                    let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { realtime.dispose(); realtime.close() }
                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.listChannels() { result, error in
                            expect(error).to(beNil())
                            guard let result = result else {
                                fail("PaginatedResult should not be empty"); done(); return
                            }
                            expect(result.items as [String]).to(contain(allSubscriptionsChannels + [subscription.channel]))
                            done()
                        }
                    }
                }
            }

            // RSH1c4
            context("remove") {
                it("should remove a subscription") {
                    let options = AblyTests.commonAppSetup()
                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }
                    let testProxyHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                    realtime.internal.rest.httpExecutor = testProxyHTTPExecutor

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.remove(subscription) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    guard let request = testProxyHTTPExecutor.requests.first else {
                        fail("No requests found")
                        return
                    }

                    expect(request.httpMethod).to(equal("DELETE"))
                    expect(request.allHTTPHeaderFields?["X-Ably-DeviceToken"]).to(beNil())
                    expect(request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]).to(beNil())

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.list(["channel": quxChannelName]) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be empty"); done(); return
                            }
                            expect(result.items.count) == 0
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }

                context("push device authentication") {
                    it("should include DeviceIdentityToken HTTP header") {
                        let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { realtime.dispose(); realtime.close() }
                        realtime.internal.rest.httpExecutor = mockHttpExecutor

                        let testIdentityTokenDetails = ARTDeviceIdentityTokenDetails(
                            token: "123456",
                            issued: Date(),
                            expires: Date.distantFuture,
                            capability: "",
                            clientId: ""
                        )

                        expect(localDevice.identityTokenDetails).to(beNil())
                        realtime.internal.rest.device.setAndPersistIdentityTokenDetails(testIdentityTokenDetails)
                        defer { realtime.internal.rest.device.setAndPersistIdentityTokenDetails(nil) }

                        let subscription = ARTPushChannelSubscription(deviceId: localDevice.id, channel: quxChannelName)

                        waitUntil(timeout: testTimeout) { done in
                            realtime.push.admin.channelSubscriptions.remove(subscription) { error in
                                expect(error).to(beNil())
                                done()
                            }
                        }

                        guard let request = mockHttpExecutor.requests.first else {
                            fail("No requests found")
                            return
                        }

                        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceToken"]
                        expect(authorization).to(equal(testIdentityTokenDetails.token.base64Encoded()))
                    }

                    it("should include DeviceSecret HTTP header") {
                        let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { realtime.dispose(); realtime.close() }
                        realtime.internal.rest.httpExecutor = mockHttpExecutor

                        let subscription = ARTPushChannelSubscription(deviceId: localDevice.id, channel: quxChannelName)

                        waitUntil(timeout: testTimeout) { done in
                            realtime.push.admin.channelSubscriptions.remove(subscription) { error in
                                expect(error).to(beNil())
                                done()
                            }
                        }

                        guard let request = mockHttpExecutor.requests.first else {
                            fail("No requests found")
                            return
                        }

                        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]
                        expect(authorization).to(equal(localDevice.secret))
                    }
                }
            }

            // RSH1c5
            context("removeWhere") {
                it("should remove by cliendId") {
                    let options = AblyTests.commonAppSetup()
                    options.pushFullWait = true
                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }

                    let params = [
                        "clientId": "clientB"
                    ]

                    let expectedRemoved = [
                        self.subscriptionFooClientB,
                        self.subscriptionBarClientB
                    ]

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.list(params) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be empty"); done(); return
                            }
                            expect(result.items).to(contain(expectedRemoved))
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.removeWhere(params) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.list(params) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be empty"); done(); return
                            }
                            expect(result.items.count) == 0
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(expectedRemoved.count, done: done)
                        for removedSubscription in expectedRemoved {
                            realtime.push.admin.channelSubscriptions.save(removedSubscription) { error in
                                expect(error).to(beNil())
                                partialDone()
                            }
                        }
                    }
                }

                it("should remove by cliendId and channel") {
                    let options = AblyTests.commonAppSetup()
                    options.pushFullWait = true
                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }

                    let params = [
                        "clientId": "clientB",
                        "channel": "pushenabled:foo"
                    ]

                    let expectedRemoved = [
                        self.subscriptionFooClientB,
                    ]

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.list(params) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be empty"); done(); return
                            }
                            expect(result.items).to(contain(expectedRemoved))
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.removeWhere(params) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.list(params) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be empty"); done(); return
                            }
                            expect(result.items.count) == 0
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }

                it("should remove by deviceId") {
                    let options = AblyTests.commonAppSetup()
                    options.pushFullWait = true
                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }

                    let params = [
                        "deviceId": "deviceDetails2ClientA",
                    ]

                    let expectedRemoved = [
                        self.subscriptionFooDevice2,
                        self.subscriptionBarDevice2,
                    ]

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.list(params) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be empty"); done(); return
                            }
                            expect(result.items).to(contain(expectedRemoved))
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.removeWhere(params) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.list(params) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be empty"); done(); return
                            }
                            expect(result.items.count) == 0
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }

                it("should not remove by inexistent deviceId") {
                    let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { realtime.dispose(); realtime.close() }

                    let params = [
                        "deviceId": "madeup",
                    ]

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.list(params) { result, error in
                            guard let result = result else {
                                fail("PaginatedResult should not be empty"); done(); return
                            }
                            expect(result.items.count) == 0
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        realtime.push.admin.channelSubscriptions.removeWhere(params) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }
            }

        }

        describe("local device") {

            it("should include an id and a secret") {
                expect(localDevice.id).toNot(beNil())
                expect(localDevice.secret).toNot(beNil())
                expect(localDevice.identityTokenDetails).to(beNil())
            }

        }

    }

}
