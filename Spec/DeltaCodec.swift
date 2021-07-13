//
//  DeltaCodec.swift
//  Ably
//
//  Created by Ricardo Pereira on 06/02/2020.
//  Copyright © 2020 Ably. All rights reserved.
//

import Ably
import Quick
import Nimble
import AblyDeltaCodec

class DeltaCodec: QuickSpec {
    override func spec() {
        describe("DeltaCodec") {

            context("decoding") {

                let testData: [String] = [
                    "{ foo: \"bar\", count: 1, status: \"active\" }",
                    "{ foo: \"bar\", count: 2, status: \"active\" }",
                    "{ foo: \"bar\", count: 2, status: \"inactive\" }",
                    "{ foo: \"bar\", count: 3, status: \"inactive\" }",
                    "{ foo: \"bar\", count: 3, status: \"active\" }"
                ]

                // RTL19
                it("should decode vcdiff encoded messages") {
                    let options = AblyTests.commonAppSetup()
                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }

                    let channelOptions = ARTRealtimeChannelOptions()
                    channelOptions.modes = [.subscribe, .publish]
                    channelOptions.params = [
                        "delta": "vcdiff"
                    ]

                    let channel = client.channels.get("foo", options: channelOptions)

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach() { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    guard let transport = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport is not be assigned"); return
                    }

                    var receivedMessages: [ARTMessage] = []
                    channel.subscribe { message in
                        receivedMessages.append(message)
                    }

                    for (i, data) in testData.enumerated() {
                        channel.publish(String(i), data: data)
                    }

                    expect(channel.errorReason).to(beNil())
                    expect(receivedMessages).toEventually(haveCount(testData.count))

                    for (i, message) in receivedMessages.enumerated() {
                        if let name = message.name, let expectedMessageIndex = Int(name) {
                            expect(i).to(equal(expectedMessageIndex))
                            expect(message.data as? String).to(equal(testData[expectedMessageIndex]))
                        }
                        else {
                            fail("Received message has an unexpected 'id': \(message)")
                        }
                    }

                    channel.unsubscribe()

                    let protocolMessages = transport.protocolMessagesReceived.filter({ $0.action == .message })
                    let messagesEncoding = (protocolMessages.reduce([], { $0 + ($1.messages ?? []) }).compactMap({ $0.encoding }))
                    expect(messagesEncoding).to(allPass(equal("utf-8/vcdiff")))
                }

                // RTL20
                it("should fail and recover when the vcdiff messages are out of order") {
                    let options = AblyTests.commonAppSetup()
                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }
                    let channelOptions = ARTRealtimeChannelOptions()
                    channelOptions.params = ["delta": "vcdiff"]
                    let channel = client.channels.get("foo", options: channelOptions)

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach() { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    guard let transport = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport is not be assigned"); return
                    }

                    transport.setBeforeIncomingMessageModifier({ protocolMessage in
                        if protocolMessage.action == .message,
                            let thirdMessage = protocolMessage.messages?.filter({ $0.name == "2" }).first {
                            thirdMessage.extras = [
                                "delta": [
                                    "format": "vcdiff",
                                    "from": "foo:1:0"
                                ]
                            ] as NSDictionary
                            transport.setBeforeIncomingMessageModifier(nil)
                        }
                        return protocolMessage
                    })

                    var receivedMessages: [ARTMessage] = []
                    channel.subscribe { message in
                        receivedMessages.append(message)
                    }

                    for (i, data) in testData.enumerated() {
                        channel.publish(String(i), data: data)
                    }

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channel.once(.attaching) { stateChange in
                            expect(receivedMessages).to(haveCount(testData.count - 3)) //messages discarded
                            expect(stateChange?.reason?.code).to(equal(40018))
                            partialDone()
                        }
                        channel.once(.attached) { stateChange in
                            partialDone()
                        }
                    }

                    expect(receivedMessages).toEventually(haveCount(testData.count))
                }

                // RTL18
                it("should recover when the vcdiff message decoding fails") {
                    let options = AblyTests.commonAppSetup()
                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }
                    let channelOptions = ARTRealtimeChannelOptions()
                    channelOptions.params = ["delta": "vcdiff"]
                    let channel = client.channels.get("foo", options: channelOptions)

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach() { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    guard let transport = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport is not be assigned"); return
                    }

                    transport.setBeforeIncomingMessageModifier({ protocolMessage in
                        if protocolMessage.action == .message,
                            let thirdMessage = protocolMessage.messages?.filter({ $0.name == "2" }).first {
                            thirdMessage.data = Data() //invalid delta
                            transport.setBeforeIncomingMessageModifier(nil)
                        }
                        return protocolMessage
                    })

                    var receivedMessages: [ARTMessage] = []
                    channel.subscribe { message in
                        receivedMessages.append(message)
                    }

                    for (i, data) in testData.enumerated() {
                        channel.publish(String(i), data: data)
                    }

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channel.once(.attaching) { stateChange in
                            expect(receivedMessages).to(haveCount(testData.count - 3)) //messages discarded
                            guard let errorReason = stateChange?.reason else {
                                fail("Reason should not be empty"); partialDone(); return
                            }
                            expect(errorReason.code).to(equal(40018))
                            expect(errorReason.message.lowercased()).to(contain("failed to decode data"))
                            partialDone()
                        }
                        channel.once(.attached) { stateChange in
                            partialDone()
                        }
                    }

                    expect(receivedMessages).toEventually(haveCount(testData.count))
                }

            }

        }
    }
}
