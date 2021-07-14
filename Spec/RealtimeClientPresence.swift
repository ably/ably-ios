//
//  RealtimeClientPresence.swift
//  Ably
//
//  Created by Ricardo Pereira on 07/03/16.
//  Copyright © 2016 Ably. All rights reserved.
//

import Ably
import Quick
import Nimble
import Foundation
import Aspects

class RealtimeClientPresence: QuickSpec {

    override func setUp() {
        super.setUp()
        AsyncDefaults.timeout = testTimeout
    }

    override func spec() {
        describe("Presence") {

            // RTP1
            context("ProtocolMessage bit flag") {
                let channelName = NSUUID().uuidString

                // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
                xit("when no members are present") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    let client = ARTRealtime(options: options)
                    client.internal.setTransport(TestProxyTransport.self)
                    client.connect()
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get(channelName)
                    channel.attach()

                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

                    let transport = client.internal.transport as! TestProxyTransport
                    let attached = transport.protocolMessagesReceived.filter({ $0.action == .attached })[0]

                    expect(attached.flags & 0x1).to(equal(0))
                    expect(attached.hasPresence).to(beFalse())
                    expect(channel.presence.syncComplete).to(beFalse())
                    expect(channel.internal.presenceMap.syncComplete).to(beFalse())
                }

                it("when members are present") {
                    let options = AblyTests.commonAppSetup()

                    var disposable = [ARTRealtime]()
                    defer {
                        for clientItem in disposable {
                            clientItem.dispose()
                            clientItem.close()
                        }
                    }

                    disposable += [AblyTests.addMembersSequentiallyToChannel(channelName, members: 250, options: options)]

                    options.autoConnect = false
                    let client = ARTRealtime(options: options)
                    client.internal.setTransport(TestProxyTransport.self)
                    client.connect()
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get(channelName)
                    channel.attach()

                    expect(channel.presence.syncComplete).to(beFalse())
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

                    let transport = client.internal.transport as! TestProxyTransport
                    let attached = transport.protocolMessagesReceived.filter({ $0.action == .attached })[0]

                    // There are members present on the channel
                    expect(attached.flags & 0x1).to(equal(1))
                    expect(attached.hasPresence).to(beTrue())
                    
                    expect(channel.presence.syncComplete).toEventually(beTrue(), timeout: testTimeout)

                    expect(transport.protocolMessagesReceived.filter({ $0.action == .sync })).to(haveCount(3))
                }

            }

            // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
            // RTP3
            xit("should complete the SYNC operation when the connection is disconnected unexpectedly") {
                let membersCount = 110

                let options = AblyTests.commonAppSetup()
                var clientSecondary: ARTRealtime!
                defer { clientSecondary.dispose(); clientSecondary.close() }

                clientSecondary = AblyTests.addMembersSequentiallyToChannel("test", members: membersCount, options: options)

                let client = AblyTests.newRealtime(options)
                defer { client.dispose(); client.close() }
                let channel = client.channels.get("test")

                var lastSyncSerial: String?
                waitUntil(timeout: testTimeout) { done in
                    let partialDone = AblyTests.splitDone(2, done: done)
                    guard let transport = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport is not set"); return
                    }
                    transport.afterProcessingReceivedMessage = { protocolMessage in
                        if protocolMessage.action == .sync {
                            lastSyncSerial = protocolMessage.channelSerial
                            expect(lastSyncSerial).toNot(beNil())
                            client.internal.onDisconnected()
                            partialDone()
                            transport.afterProcessingReceivedMessage = nil
                        }
                    }
                    channel.attach() { _ in
                        partialDone()
                    }
                }

                expect(channel.internal.presenceMap.members).toNot(haveCount(membersCount))
                expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connecting), timeout: DispatchTimeInterval.milliseconds(Int(1000.0 * (options.disconnectedRetryTimeout + 1.0))))
                expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

                // Client library requests a SYNC resume by sending a SYNC ProtocolMessage with the last received sync serial number
                guard let transport = client.internal.transport as? TestProxyTransport else {
                    fail("TestProxyTransport is not set"); return
                }

                let syncSentProtocolMessages = transport.protocolMessagesSent.filter({ $0.action == .sync })
                guard let syncSentMessage = syncSentProtocolMessages.last, syncSentProtocolMessages.count == 1 else {
                    fail("Should send one SYNC protocol message"); return
                }
                expect(syncSentMessage.channelSerial).to(equal(lastSyncSerial))

                expect(transport.protocolMessagesReceived.filter{ $0.action == .sync }).toEventually(haveCount(2), timeout: testTimeout)

                waitUntil(timeout: testTimeout) { done in
                    channel.presence.get { members, error in
                        expect(error).to(beNil())
                        guard let members = members else {
                            fail("No present members"); done(); return
                        }
                        expect(members).to(haveCount(membersCount))
                        done()
                    }
                }
            }

            // RTP18
            context("realtime system reserves the right to initiate a sync of the presence members at any point once a channel is attached") {

                // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
                // RTP18a, RTP18b
                xit("should do a new sync whenever a SYNC ProtocolMessage is received with a channel attribute and a new sync sequence identifier in the channelSerial attribute") {
                    let options = AblyTests.commonAppSetup()
                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }
                    let channelName = NSUUID().uuidString
                    let channel = client.channels.get(channelName)
                    waitUntil(timeout: testTimeout) { done in
                        channel.attach() { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    guard let transport = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport is not set"); return
                    }

                    expect(channel.internal.presenceMap.syncInProgress).to(beFalse())
                    expect(channel.internal.presenceMap.members).to(beEmpty())

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(.present) { msg in
                            if msg.clientId != "a" {
                                return
                            }
                            expect(channel.presence.syncComplete).to(beFalse())
                            var aClientHasLeft = false;
                            channel.presence.subscribe(.leave) { _ in
                                if (aClientHasLeft) {
                                    return
                                }
                                aClientHasLeft = true;
                                done()
                            }
                        }

                        guard let lastConnectionSerial = transport.protocolMessagesReceived.last?.connectionSerial else {
                            fail("No protocol message has been received yet"); done(); return
                        }

                        // Inject a SYNC Presence message (first page)
                        let sync1Message = ARTProtocolMessage()
                        sync1Message.action = .sync
                        sync1Message.channel = channel.name
                        sync1Message.channelSerial = "sequenceid:cursor"
                        sync1Message.connectionSerial = lastConnectionSerial + 1
                        sync1Message.timestamp = Date()
                        sync1Message.presence = [
                            ARTPresenceMessage(clientId: "a", action: .present, connectionId: "another", id: "another:0:0"),
                            ARTPresenceMessage(clientId: "b", action: .present, connectionId: "another", id: "another:0:1"),
                        ]
                        transport.receive(sync1Message)

                        // Inject a SYNC Presence message (last page)
                        let sync2Message = ARTProtocolMessage()
                        sync2Message.action = .sync
                        sync2Message.channel = channel.name
                        sync2Message.channelSerial = "sequenceid:" //indicates SYNC is complete
                        sync2Message.connectionSerial = lastConnectionSerial + 2
                        sync2Message.timestamp = Date()
                        sync2Message.presence = [
                            ARTPresenceMessage(clientId: "a", action: .leave, connectionId: "another", id: "another:1:0"),
                        ]
                        delay(0.5) {
                            transport.receive(sync2Message)
                        }
                    }

                    expect(channel.presence.syncComplete).to(beTrue())
                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get { members, error in
                            expect(error).to(beNil())
                            guard let members = members, members.count == 1 else {
                                fail("Should at least have 1 member"); done(); return
                            }
                            expect(members[0].clientId).to(equal("b"))
                            done()
                        }
                    }
                }

                // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
                // RTP18c, RTP18b
                xit("when a SYNC is sent with no channelSerial attribute then the sync data is entirely contained within that ProtocolMessage") {
                    let options = AblyTests.commonAppSetup()
                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }
                    let channelName = NSUUID().uuidString
                    let channel = client.channels.get(channelName)
                    waitUntil(timeout: testTimeout) { done in
                        channel.attach() { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    guard let transport = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport is not set"); return
                    }

                    expect(channel.internal.presenceMap.syncInProgress).to(beFalse())
                    expect(channel.internal.presenceMap.members).to(beEmpty())

                    waitUntil(timeout: testTimeout) { done in
                        var aClientHasLeft = false;
                        channel.presence.subscribe(.leave) { error in
                            if (aClientHasLeft) {
                                return
                            }
                            aClientHasLeft = true;
                            done()
                        }

                        guard let lastConnectionSerial = transport.protocolMessagesReceived.last?.connectionSerial else {
                            fail("No protocol message has been received yet"); done(); return
                        }

                        // Inject a SYNC Presence message (entirely contained)
                        let syncMessage = ARTProtocolMessage()
                        syncMessage.action = .sync
                        syncMessage.channel = channel.name
                        syncMessage.connectionSerial = lastConnectionSerial + 1
                        syncMessage.timestamp = Date()
                        syncMessage.presence = [
                            ARTPresenceMessage(clientId: "a", action: .present, connectionId: "another", id: "another:0:0"),
                            ARTPresenceMessage(clientId: "b", action: .present, connectionId: "another", id: "another:0:1"),
                            ARTPresenceMessage(clientId: "a", action: .leave, connectionId: "another", id: "another:1:0"),
                        ]
                        transport.receive(syncMessage)
                    }

                    expect(channel.presence.syncComplete).to(beTrue())
                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get { members, error in
                            expect(error).to(beNil())
                            guard let members = members, members.count == 1 else {
                                fail("Should at least have 1 member"); done(); return
                            }
                            expect(members[0].clientId).to(equal("b"))
                            done()
                        }
                    }
                }

            }

            // RTP19
            context("PresenceMap has existing members when a SYNC is started") {

                it("should ensure that members no longer present on the channel are removed from the local PresenceMap once the sync is complete") {
                    let options = AblyTests.commonAppSetup()
                    let channelName = NSUUID().uuidString
                    var clientMembers: ARTRealtime?
                    defer { clientMembers?.dispose(); clientMembers?.close() }
                    clientMembers = AblyTests.addMembersSequentiallyToChannel(channelName, members: 2, options: options)

                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get(channelName)
                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get { members, error in
                            expect(error).to(beNil())
                            expect(members).to(haveCount(2)) //synced
                            done()
                        }
                    }

                    expect(channel.internal.presenceMap.members).to(haveCount(2))
                    // Inject a local member
                    let localMember = ARTPresenceMessage(clientId: NSUUID().uuidString, action: .enter, connectionId: "another", id: "another:0:0")
                    channel.internal.presenceMap.add(localMember)
                    expect(channel.internal.presenceMap.members).to(haveCount(3))
                    expect(channel.internal.presenceMap.members.filter{ memberKey, _ in memberKey.contains(localMember.clientId!) }).to(haveCount(1))

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get { members, error in
                            expect(error).to(beNil())
                            guard let members = members, members.count == 3 else {
                                fail("Should at least have 3 members"); done(); return
                            }
                            expect(members.filter{ $0.clientId == localMember.clientId }).to(haveCount(1))
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(.leave) { leave in
                            expect(leave.clientId).to(equal(localMember.clientId))
                            done()
                        }

                        // Request a sync   
                        let syncMessage = ARTProtocolMessage()
                        syncMessage.action = .sync
                        syncMessage.channel = channel.name
                        guard let transport = client.internal.transport as? TestProxyTransport else {
                            fail("TestProxyTransport is not set"); done(); return
                        }
                        transport.send(syncMessage)
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get { members, error in
                            expect(error).to(beNil())
                            guard let members = members, members.count == 2 else {
                                fail("Should at least have 2 members"); done(); return
                            }
                            expect(members.filter{ $0.clientId == localMember.clientId }).to(beEmpty())
                            done()
                        }
                    }
                }

                // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
                // RTP19a
                xit("should emit a LEAVE event for each existing member if the PresenceMap has existing members when an ATTACHED message is received without a HAS_PRESENCE flag") {
                    let options = AblyTests.commonAppSetup()
                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }
                    let channelName = NSUUID().uuidString
                    let channel = client.channels.get(channelName)

                    // Inject local members
                    channel.internal.presenceMap.add(ARTPresenceMessage(clientId: "tester1", action: .enter, connectionId: "another", id: "another:0:0"))
                    channel.internal.presenceMap.add(ARTPresenceMessage(clientId: "tester2", action: .enter, connectionId: "another", id: "another:0:1"))

                    guard let transport = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport is not set"); return
                    }

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(4, done: done)
                        transport.afterProcessingReceivedMessage = { protocolMessage in
                            if protocolMessage.action == .attached {
                                expect(protocolMessage.hasPresence).to(beFalse())
                                partialDone()
                            }
                        }
                        channel.presence.subscribe(.leave) { leave in
                            expect(leave.clientId?.hasPrefix("tester")).to(beTrue())
                            expect(leave.action).to(equal(ARTPresenceAction.leave))
                            expect(leave.timestamp).to(beCloseTo(Date(), within: 0.5))
                            expect(leave.id).to(beNil())
                            partialDone() //2 times
                        }
                        channel.attach { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get { members, error in
                            expect(error).to(beNil())
                            expect(members).to(beEmpty())
                            done()
                        }
                    }
                }

            }

            // RTP4
            it("should receive all 250 members") {
                let options = AblyTests.commonAppSetup()
                var clientSource: ARTRealtime!
                defer { clientSource.dispose(); clientSource.close() }
                clientSource = AblyTests.addMembersSequentiallyToChannel("test", members: 250, options: options)

                let clientTarget = ARTRealtime(options: options)
                defer { clientTarget.close() }
                let channel = clientTarget.channels.get("test")

                waitUntil(timeout: testTimeout) { done in
                    var pending = 250
                    channel.presence.subscribe { member in
                        expect(member.action).to(equal(ARTPresenceAction.present))
                        pending -= 1
                        if pending == 0 {
                            done()
                        }
                    }
                }

                waitUntil(timeout: testTimeout) { done in
                    channel.presence.get() { members, error in
                        expect(error).to(beNil())
                        expect(members).to(haveCount(250))
                        done()
                    }
                }
            }

            // RTP6
            context("subscribe") {

                // RTP6a
                xit("with no arguments should subscribe a listener to all presence messages") {
                    let options = AblyTests.commonAppSetup()

                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }
                    let channel1 = client1.channels.get("test")

                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }
                    let channel2 = client2.channels.get("test")

                    var receivedMembers = [ARTPresenceMessage]()
                    channel1.presence.subscribe { member in
                        receivedMembers.append(member)
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel2.presence.enterClient("john", data: "online") { err in
                            channel2.presence.updateClient("john", data: "away") { err in
                                channel2.presence.leaveClient("john", data: nil) { err in
                                    done()
                                }
                            }
                        }
                    }

                    expect(receivedMembers).toEventually(haveCount(3), timeout: testTimeout)
                    if receivedMembers.count != 3 {
                        return
                    }

                    expect(receivedMembers[0].action).to(equal(ARTPresenceAction.enter))
                    expect(receivedMembers[0].data as? NSObject).to(equal("online" as NSObject?))
                    expect(receivedMembers[0].clientId).to(equal("john"))

                    expect(receivedMembers[1].action).to(equal(ARTPresenceAction.update))
                    expect(receivedMembers[1].data as? NSObject).to(equal("away" as NSObject?))
                    expect(receivedMembers[1].clientId).to(equal("john"))

                    expect(receivedMembers[2].action).to(equal(ARTPresenceAction.leave))
                    expect(receivedMembers[2].data as? NSObject).to(equal("away" as NSObject?))
                    expect(receivedMembers[2].clientId).to(equal("john"))
                }

            }

            // RTP7
            context("unsubscribe") {

                // RTP7a
                it("with no arguments unsubscribes the listener if previously subscribed with an action-specific subscription") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    let listener = channel.presence.subscribe { _ in }!
                    expect(channel.internal.presenceEventEmitter.anyListeners).to(haveCount(1))
                    channel.presence.unsubscribe(listener)
                    expect(channel.internal.presenceEventEmitter.anyListeners).to(haveCount(0))
                }

            }

            // RTP5
            context("Channel state change side effects") {

                // RTP5a
                context("if the channel enters the FAILED state") {

                    it("all queued presence messages should fail immediately") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.dispose(); client.close() }
                        let channel = client.channels.get("test")

                        waitUntil(timeout: testTimeout) { done in
                            let protocolError = AblyTests.newErrorProtocolMessage()
                            channel.presence.enterClient("user", data: nil) { error in
                                expect(error).to(beIdenticalTo(protocolError.error))
                                expect(channel.presence.internal.pendingPresence).to(haveCount(0))
                                done()
                            }
                            expect(channel.presence.internal.pendingPresence).to(haveCount(1))
                            client.internal.rest.queue.async {
                                channel.internal.onError(protocolError)
                            }
                        }
                    }

                    it("should clear the PresenceMap including local members and does not emit any presence events") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.dispose(); client.close() }
                        let channel = client.channels.get("test")
                        waitUntil(timeout: testTimeout) { done in
                            let partialDone = AblyTests.splitDone(2, done: done)
                            channel.presence.enterClient("user", data: nil) { error in
                                expect(error).to(beNil())
                                partialDone()
                            }
                            channel.presence.subscribe { message in
                                expect(message.clientId).to(equal("user"))
                                channel.presence.unsubscribe()
                                partialDone()
                            }
                        }

                        expect(channel.internal.presenceMap.members).to(haveCount(1))
                        expect(channel.internal.presenceMap.localMembers).to(haveCount(1))

                        channel.subscribe() { _ in
                            fail("Shouldn't receive any presence event")
                        }
                        defer { channel.off() }

                        waitUntil(timeout: testTimeout) { done in
                            channel.once(.failed) { _ in
                                expect(channel.internal.presenceMap.members).to(beEmpty())
                                expect(channel.internal.presenceMap.localMembers).to(beEmpty())
                                done()
                            }
                            AblyTests.queue.async {
                                channel.internal.onError(AblyTests.newErrorProtocolMessage())
                            }
                        }
                    }

                }

                // RTP5a
                context("if the channel enters the DETACHED state") {

                    it("all queued presence messages should fail immediately") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.dispose(); client.close() }
                        let channel = client.channels.get("test")

                        waitUntil(timeout: testTimeout) { done in
                            channel.once(.attaching) { _ in
                                channel.detach()
                            }
                            channel.presence.enterClient("user", data: nil) { error in
                                expect(error).toNot(beNil())
                                expect(client.internal.queuedMessages).to(haveCount(0))
                                done()
                            }
                        }
                    }

                    it("should clear the PresenceMap including local members and does not emit any presence events") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.dispose(); client.close() }
                        let channel = client.channels.get("test")
                        waitUntil(timeout: testTimeout) { done in
                            let partialDone = AblyTests.splitDone(2, done: done)
                            channel.presence.enterClient("user", data: nil) { error in
                                expect(error).to(beNil())
                                partialDone()
                            }
                            channel.presence.subscribe { message in
                                expect(message.clientId).to(equal("user"))
                                channel.presence.unsubscribe()
                                partialDone()
                            }
                        }

                        expect(channel.internal.presenceMap.members).to(haveCount(1))
                        expect(channel.internal.presenceMap.localMembers).to(haveCount(1))

                        channel.subscribe() { _ in
                            fail("Shouldn't receive any presence event")
                        }
                        defer { channel.off() }

                        waitUntil(timeout: testTimeout) { done in
                            channel.once(.detached) { _ in
                                expect(channel.internal.presenceMap.members).to(beEmpty())
                                expect(channel.internal.presenceMap.localMembers).to(beEmpty())
                                done()
                            }
                            channel.detach()
                        }
                    }

                }

                // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
                // RTP5b
                xit("if a channel enters the ATTACHED state then all queued presence messages will be sent immediately and a presence SYNC may be initiated") {
                    let options = AblyTests.commonAppSetup()
                    let client1 = AblyTests.newRealtime(options)
                    defer { client1.dispose(); client1.close() }
                    let channel1 = client1.channels.get(NSUUID().uuidString)

                    waitUntil(timeout: testTimeout) { done in
                        channel1.presence.enterClient("Client 1", data: nil) { errorInfo in
                            expect(errorInfo).to(beNil())
                            done()
                        }
                    }

                    let client2 = AblyTests.newRealtime(options)
                    defer { client2.dispose(); client2.close() }
                    let channel2 = client2.channels.get(channel1.name)

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channel2.presence.enterClient("Client 2", data: nil) { error in
                            expect(error).to(beNil())
                            expect(client2.internal.queuedMessages).to(haveCount(0))
                            expect(channel2.state).to(equal(ARTRealtimeChannelState.attached))
                            partialDone()
                        }
                        channel2.presence.subscribe(.enter) { _ in
                            if channel2.presence.syncComplete {
                                expect(channel2.internal.presenceMap.members).to(haveCount(2))
                            }
                            else {
                                expect(channel2.internal.presenceMap.members).to(haveCount(1))
                            }
                            channel2.presence.unsubscribe()
                            partialDone()
                        }

                        expect(client2.internal.queuedMessages).to(haveCount(1))
                        expect(channel2.presence.syncComplete).to(beFalse())
                        expect(channel2.internal.presenceMap.members).to(haveCount(0))
                    }

                    guard let transport = client2.internal.transport as? TestProxyTransport else {
                        fail("Transport should be a test proxy"); return
                    }

                    expect(transport.protocolMessagesReceived.filter{ $0.action == .sync }).to(haveCount(1))

                    expect(channel2.presence.syncComplete).toEventually(beTrue(), timeout: testTimeout)
                    expect(channel2.internal.presenceMap.members).to(haveCount(2))
                }

                // RTP5f
                context("channel enters the SUSPENDED state") {

                    it("all queued presence messages should fail immediately") {
                        let options = AblyTests.commonAppSetup()
                        let client = AblyTests.newRealtime(options)
                        defer { client.dispose(); client.close() }
                        let channelName = NSUUID().uuidString
                        let channel = client.channels.get(channelName)

                        waitUntil(timeout: testTimeout) { done in
                            let partialDone = AblyTests.splitDone(3, done: done)
                            channel.once(.attaching) { stateChange in
                                expect(stateChange?.reason).to(beNil())
                                expect(channel.presence.internal.pendingPresence.count) == 1
                                AblyTests.queue.async {
                                    channel.internal.setSuspended(ARTStatus.state(.error, info: ARTErrorInfo.create(withCode: 1234, message: "unknown error")))
                                }
                                partialDone()
                            }
                            channel.once(.suspended) { stateChange in
                                // All queued presence messages will fail immediately
                                expect(channel.presence.internal.pendingPresence.count) == 0
                                partialDone()
                            }
                            channel.presence.enterClient("tester", data: nil) { error in
                                guard let error = error else {
                                    fail("Error is nil"); partialDone(); return
                                }
                                expect((error ).code) == 1234
                                expect(error.message).to(contain("unknown error"))
                                partialDone()
                            }
                        }
                    }

                    xit("should maintain the PresenceMap and any members present before and after the sync should not emit presence events") {
                        let options = AblyTests.commonAppSetup()
                        let channelName = NSUUID().uuidString

                        var clientMembers: ARTRealtime?
                        clientMembers = AblyTests.addMembersSequentiallyToChannel(channelName, members: 3, options: options)
                        defer { clientMembers?.dispose(); clientMembers?.close() }

                        options.clientId = "tester"
                        options.tokenDetails = getTestTokenDetails(key: options.key!, clientId: options.clientId, ttl: 5.0)
                        let client = AblyTests.newRealtime(options)
                        defer { client.dispose(); client.close() }
                        let channel = client.channels.get(channelName)
                        waitUntil(timeout: testTimeout) { done in
                            let partialDone = AblyTests.splitDone(3, done: done)
                            channel.presence.enter(nil) { error in
                                expect(error).to(beNil())
                                partialDone()
                            }
                            channel.presence.get { members, error in
                                expect(error).to(beNil())
                                expect(members).to(haveCount(3))
                                partialDone()
                            }
                            channel.presence.subscribe(.enter) { message in
                                if message.clientId == "tester" {
                                    channel.presence.unsubscribe()
                                    partialDone()
                                }
                            }
                        }

                        waitUntil(timeout: testTimeout) { done in
                            let partialDone = AblyTests.splitDone(4, done: done)
                            channel.presence.subscribe { presence in
                                expect(presence.action).to(equal(ARTPresenceAction.leave))
                                expect(presence.clientId).to(equal("tester"))
                                partialDone()
                            }
                            channel.once(.suspended) { stateChange in
                                expect(channel.internal.presenceMap.members).to(haveCount(4))
                                expect(channel.internal.presenceMap.localMembers).to(haveCount(1))
                                partialDone()
                            }
                            channel.once(.attached) { stateChange in
                                expect(stateChange?.reason).to(beNil())
                                channel.presence.leave(nil) { error in
                                    expect(error).to(beNil())
                                    partialDone()
                                }
                                partialDone()
                            }
                            channel.internal.setSuspended(ARTStatus.state(.ok))
                        }

                        channel.presence.unsubscribe()
                        waitUntil(timeout: testTimeout) { done in
                            channel.presence.get { members, error in
                                expect(error).to(beNil())
                                guard let members = members else {
                                    fail("Members is nil"); done(); return
                                }
                                expect(members).to(haveCount(3))
                                expect(members).to(allPass({ (member: ARTPresenceMessage?) in member!.action != .absent }))
                                expect(channel.internal.presenceMap.members).to(haveCount(3))
                                expect(channel.internal.presenceMap.localMembers).to(beEmpty())
                                done()
                            }
                        }
                    }

                }

            }

            // RTP8
            context("enter") {

                // RTP8a
                it("should enter the current client, optionally with the data provided") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"

                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }
                    let channel1 = client1.channels.get("test")

                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }
                    let channel2 = client2.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel1.attach { err in 
                            expect(err).to(beNil())
                            channel1.presence.subscribe(.enter) { member in
                                expect(member.clientId).to(equal(options.clientId))
                                expect(member.data as? NSObject).to(equal("online" as NSObject?))
                                done()
                            }
                            channel2.presence.enter("online")
                        }
                    }
                }

            }

            // RTP7
            context("unsubscribe") {

                // RTP7b
                it("with a single action argument unsubscribes the provided listener to all presence messages for that action") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    let listener = channel.presence.subscribe(.present) { _ in }!
                    expect(channel.internal.presenceEventEmitter.listeners).to(haveCount(1))
                    channel.presence.unsubscribe(.present, listener: listener)
                    expect(channel.internal.presenceEventEmitter.listeners).to(haveCount(0))
                }

            }

            // RTP6
            context("subscribe") {

                // RTP6c
                it("should implicitly attach the channel") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    expect(channel.state).to(equal(ARTRealtimeChannelState.initialized))
                    channel.presence.subscribe { _ in }
                    expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

                    channel.detach()
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.detached), timeout: testTimeout)

                    channel.presence.subscribe(.present) { _ in }
                    expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
                }

                // RTP6c
                it("should result in an error if the channel is in the FAILED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }

                    let channel = client.channels.get("test")
                    channel.internal.onError(AblyTests.newErrorProtocolMessage())
                    expect(channel.state).to(equal(ARTRealtimeChannelState.failed))

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(attachCallback: { errorInfo in
                            expect(errorInfo).toNot(beNil())

                            channel.presence.subscribe(.enter, onAttach: { errorInfo in
                                expect(errorInfo).toNot(beNil())
                                done()
                            }) { _ in }
                        }) { _ in }
                    }
                }

                // RTP6c
                it("should result in an error if the channel moves to the FAILED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        let error = AblyTests.newErrorProtocolMessage()
                        channel.presence.subscribe(attachCallback: { errorInfo in
                            expect(errorInfo).toNot(beNil())

                            channel.presence.subscribe(.enter, onAttach: { errorInfo in
                                expect(errorInfo).toNot(beNil())
                                done()
                            }) { _ in }
                        }) {_ in }
                        AblyTests.queue.async {
                            channel.internal.onError(error)
                        }
                    }
                }

            }

            // RTP6
            context("subscribe") {

                // RTP6b
                xit("with a single action argument") {
                    let options = AblyTests.commonAppSetup()

                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }
                    let channel1 = client1.channels.get("test")

                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }
                    let channel2 = client2.channels.get("test")

                    var count = 0
                    channel1.presence.subscribe(.update) { member in
                        expect(member.action).to(equal(ARTPresenceAction.update))
                        expect(member.clientId).to(equal("john"))
                        expect(member.data as? NSObject).to(equal("away" as NSObject?))
                        count += 1
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel2.presence.enterClient("john", data: "online") { error in
                            expect(error).to(beNil())
                            channel2.presence.updateClient("john", data: "away") { error in
                                expect(error).to(beNil())
                                channel2.presence.leaveClient("john", data: nil) { error in
                                    expect(error).to(beNil())
                                    done()
                                }
                            }
                        }
                    }

                    expect(count).toEventually(equal(1), timeout: testTimeout)
                }

            }

            // RTP8
            context("enter") {

                // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
                // RTP8b
                xit("optionally a callback can be provided that is called for success") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"

                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }
                    let channel1 = client1.channels.get("test")

                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }
                    let channel2 = client2.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel1.presence.subscribe(.enter) { member in
                            expect(member.clientId).to(equal(options.clientId))
                            expect(member.data as? NSObject).to(equal("online" as NSObject?))
                            done()
                        }
                        channel2.presence.enter("online") { error in
                            expect(error).to(beNil())
                        }
                    }
                }

                // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
                // RTP8b
                xit("optionally a callback can be provided that is called for failure") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"

                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }
                    let channel1 = client1.channels.get("test")

                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }
                    let channel2 = client2.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel1.presence.subscribe(.enter) { member in
                            fail("shouldn't be called")
                        }
                        let protocolError = AblyTests.newErrorProtocolMessage()
                        channel2.presence.enter("online") { error in
                            expect(error).to(beIdenticalTo(protocolError.error))
                            done()
                        }
                        delay(0.1) {
                            channel2.internal.onError(protocolError)
                        }
                    }
                }

                // RTP8c
                it("entering without an explicit PresenceMessage#clientId should implicitly use the clientId of the current connection") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channel.presence.enter("online") { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                        channel.presence.subscribe { message in
                            expect(message.clientId).to(equal("john"))
                            channel.presence.unsubscribe()
                            partialDone()
                        }
                    }

                    let transport = client.internal.transport as! TestProxyTransport
                    let sent = transport.protocolMessagesSent.filter({ $0.action == .presence })[0].presence![0]
                    expect(sent.action).to(equal(ARTPresenceAction.enter))
                    expect(sent.clientId).to(beNil())

                    let received = transport.protocolMessagesReceived.filter({ $0.action == .presence })[0].presence![0]
                    expect(received.action).to(equal(ARTPresenceAction.enter))
                    expect(received.clientId).to(equal("john"))
                }

            }

            // RTP8
            context("enter") {

                // RTP8f
                it("should result in an error immediately if the client is anonymous") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter(nil) { error in
                            expect(error!.message).to(contain("attempted to publish presence message without clientId"))
                            done()
                        }
                    }
                }

            }

            // RTP8
            context("enter") {

                // RTP8g
                it("should result in an error immediately if the channel is DETACHED") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach() { _ in
                            channel.detach() { _ in done() }
                        }
                    }
                    
                    expect(channel.state).to(equal(ARTRealtimeChannelState.detached))

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter(nil) { error in
                            expect(error?.code).to(equal(90001))
                            done()
                        }
                    }
                }

                // RTP8g
                it("should result in an error immediately if the channel is FAILED") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        AblyTests.queue.async {
                            channel.internal.onError(AblyTests.newErrorProtocolMessage())
                            done()
                        }
                    }

                    expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
                        

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter(nil) { error in
                            expect(error?.code).to(equal(90001))
                            done()
                        }
                    }
                }

            }

            // RTP8
            context("enter") {

                // RTP8i
                it("should result in an error if Ably service determines that the client is unidentified") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter(nil) { error in
                            expect(error!.message).to(contain("presence message without clientId"))
                            done()
                        }
                    }
                }

            }

            // RTP9
            context("update") {

                // RTP9a
                it("should update the data for the present member with a value") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(.enter) { member in
                            expect(member.data).to(beNil())
                            done()
                        }
                        channel.presence.enter(nil)
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(.update) { member in
                            expect(member.data as? NSObject).to(equal("online" as NSObject?))
                            done()
                        }
                        channel.presence.update("online")
                    }
                }

                // RTP9a
                xit("should update the data for the present member with null") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(.enter) { member in
                            expect(member.data as? NSObject).to(equal("online" as NSObject?))
                            done()
                        }
                        channel.presence.enter("online")
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(.update) { member in
                            expect(member.data).to(beNil())
                            done()
                        }
                        channel.presence.update(nil)
                    }
                }

            }

            // RTP9
            context("update") {

                // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
                // RTP9b
                xit("should enter current client into the channel if the client was not already entered") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    expect(channel.internal.presenceMap.members).to(haveCount(0))
                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(.enter) { member in
                            expect(member.clientId).to(equal("john"))
                            expect(member.data as? NSObject).to(equal("online" as NSObject?))
                            done()
                        }
                        channel.presence.update("online")
                    }
                }

            }

            // RTP9
            context("update") {

                // RTP9c
                it("optionally a callback can be provided that is called for success") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.update("online") { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }

                // RTP9c
                it("optionally a callback can be provided that is called for failure") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        let protocolError = AblyTests.newErrorProtocolMessage()
                        channel.once(.attaching) { _ in
                            AblyTests.queue.async {
                                channel.internal.onError(protocolError)
                            }
                        }
                        (client.internal.transport as! TestProxyTransport).actionsIgnored += [.attached]
                        channel.presence.update("online") { error in
                            expect(error).to(beIdenticalTo(protocolError.error))
                            done()
                        }
                    }
                }

                // RTP9d
                it("update without an explicit PresenceMessage#clientId should implicitly use the clientId of the current connection") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter("online") { error in
                            channel.presence.update("offline") { error in
                                expect(error).to(beNil())
                                done()
                            }
                        }
                    }

                    let transport = client.internal.transport as! TestProxyTransport
                    let sent = transport.protocolMessagesSent.filter({ $0.action == .presence })[1].presence![0]
                    expect(sent.action).to(equal(ARTPresenceAction.update))
                    expect(sent.clientId).to(beNil())

                    let receivedPresenceProtocolMessages = transport.protocolMessagesReceived.filter({ $0.action == .presence })
                    let receivedPresenceMessages = receivedPresenceProtocolMessages.flatMap({ $0.presence! })
                    let received = receivedPresenceMessages.filter({ $0.action == .update })[0]
                    expect(received.action).to(equal(ARTPresenceAction.update))
                    expect(received.clientId).to(equal("john"))
                }

            }

            // RTP10
            context("leave") {

                // RTP10a
                xit("should leave the current client from the channel and the data will be updated with the value provided") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(.enter) { member in
                            expect(member.data as? NSObject).to(equal("online" as NSObject?))
                            done()
                        }
                        channel.presence.enter("online")
                    }

                    expect(channel.internal.presenceMap.members).toEventually(haveCount(1), timeout: testTimeout)

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(.leave) { member in
                            expect(member.data as? NSObject).to(equal("offline" as NSObject?))
                            done()
                        }
                        channel.presence.leave("offline")
                    }

                    expect(channel.internal.presenceMap.members).toEventually(haveCount(0), timeout: testTimeout)
                }

                // RTP10a
                it("should leave the current client with no data") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(.enter) { member in
                            expect(member.data as? NSObject).to(equal("online" as NSObject?))
                            done()
                        }
                        channel.presence.enter("online")
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(.leave) { member in
                            expect(member.data as? NSObject).to(equal("online" as NSObject?))
                            done()
                        }
                        channel.presence.leave(nil)
                    }
                }

            }

            // RTP2
            it("should be used a PresenceMap to maintain a list of members") {
                let options = AblyTests.commonAppSetup()
                var clientSecondary: ARTRealtime!
                defer { clientSecondary.dispose(); clientSecondary.close() }
                clientSecondary = AblyTests.addMembersSequentiallyToChannel("test", members: 100, options: options)

                let client = AblyTests.newRealtime(options)
                defer { client.dispose(); client.close() }
                let channel = client.channels.get("test")

                waitUntil(timeout: testTimeout) { done in
                    channel.attach() { error in
                        expect(error).to(beNil())
                        done()
                    }
                }

                channel.presence.unsubscribe()
                waitUntil(timeout: testTimeout) { done in
                    channel.presence.get { members, error in
                        expect(error).to(beNil())
                        guard let members = members else {
                            fail("Members is nil"); done(); return
                        }
                        expect(members.count) == 100
                        done()
                    }
                }
            }

            // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
            // RTP2
            context("PresenceMap") {

                // RTP2a
                xit("all incoming presence messages must be compared for newness with the matching member already in the PresenceMap") {
                    let options = AblyTests.commonAppSetup()
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channelName = NSUUID().uuidString
                    let channel = client.channels.get(channelName)

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channel.presence.subscribe { presence in
                            expect(presence.clientId).to(equal("tester"))
                            expect(presence.action).to(equal(.enter))
                            channel.presence.unsubscribe()
                            partialDone()
                        }
                        channel.presence.enterClient("tester", data: nil) { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                    }

                    guard let intialPresenceMessage = channel.internal.presenceMap.members["\(channel.internal.connectionId):tester"] else {
                        fail("Missing Presence message"); return
                    }

                    expect(intialPresenceMessage.memberKey()).to(equal("\(client.connection.id!):tester"))

                    var compareForNewnessMethodCalls = 0
                    let hook = ARTPresenceMessage.testSuite_injectIntoClassMethod(#selector(ARTPresenceMessage.isNewerThan(_:))) {
                        compareForNewnessMethodCalls += 1
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enterClient("tester", data: nil) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    guard let updatedPresenceMessage = channel.internal.presenceMap.members["\(channel.internal.connectionId):tester"] else {
                        fail("Missing Presence message"); return
                    }

                    expect(intialPresenceMessage.memberKey()).to(equal(updatedPresenceMessage.memberKey()))
                    expect(intialPresenceMessage.timestamp).to(beLessThan(updatedPresenceMessage.timestamp))

                    expect(compareForNewnessMethodCalls) == 1

                    hook?.remove()
                }

                // RTP2b
                context("compare for newness") {

                    context("presence message has a connectionId which is not an initial substring of its id") {
                        // RTP2b1
                        it("compares them by timestamp numerically") {
                            let options = AblyTests.commonAppSetup()
                            let now = NSDate()
                            let channelName = NSUUID().uuidString
                            var clientMembers: ARTRealtime?
                            defer { clientMembers?.dispose(); clientMembers?.close() }
                            clientMembers = AblyTests.addMembersSequentiallyToChannel(channelName, members: 101, options: options)

                            let clientSubscribed = AblyTests.newRealtime(options)
                            defer { clientSubscribed.dispose(); clientSubscribed.close() }
                            let channelSubscribed = clientSubscribed.channels.get(channelName)

                            let presenceData: [ARTPresenceMessage] = [
                                ARTPresenceMessage(clientId: "a", action: .enter, connectionId: "one", id: "one:0:0", timestamp: now as Date),
                                ARTPresenceMessage(clientId: "a", action: .leave, connectionId: "one", id: "fabricated:0:1", timestamp: (now as Date) + 1),
                                ARTPresenceMessage(clientId: "b", action: .enter, connectionId: "one", id: "one:0:2", timestamp: now as Date),
                                ARTPresenceMessage(clientId: "b", action: .leave, connectionId: "one", id: "fabricated:0:3", timestamp: (now as Date) - 1),
                                ARTPresenceMessage(clientId: "c", action: .enter, connectionId: "one", id: "fabricated:0:4", timestamp: now as Date),
                                ARTPresenceMessage(clientId: "c", action: .leave, connectionId: "one", id: "fabricated:0:5", timestamp: (now as Date) - 1),
                            ]

                            guard let transport = clientSubscribed.internal.transport as? TestProxyTransport else {
                                fail("TestProxyTransport is not set"); return
                            }

                            waitUntil(timeout: testTimeout.multiplied(by: 2)) { done in
                                transport.afterProcessingReceivedMessage = { protocolMessage in
                                    // Receive the first Sync message from Ably service
                                    if protocolMessage.action == .sync {

                                        // Inject a fabricated Presence message
                                        let presenceMessage = ARTProtocolMessage()
                                        presenceMessage.action = .presence
                                        presenceMessage.channel = protocolMessage.channel
                                        presenceMessage.connectionSerial = protocolMessage.connectionSerial + 1
                                        presenceMessage.timestamp = Date()
                                        presenceMessage.presence = presenceData

                                        transport.receive(presenceMessage)

                                        // Simulate an end to the sync
                                        let endSyncMessage = ARTProtocolMessage()
                                        endSyncMessage.action = .sync
                                        endSyncMessage.channel = protocolMessage.channel
                                        endSyncMessage.channelSerial = "validserialprefix:" //with no part after the `:` this indicates the end to the SYNC
                                        endSyncMessage.connectionSerial = protocolMessage.connectionSerial + 2
                                        endSyncMessage.timestamp = Date()

                                        transport.afterProcessingReceivedMessage = nil
                                        transport.receive(endSyncMessage)

                                        // Stop the next sync message from Ably service because we already injected the end of the sync
                                        transport.actionsIgnored = [.sync]

                                        done()
                                    }
                                }
                                channelSubscribed.attach()
                            }

                            waitUntil(timeout: testTimeout) { done in
                                channelSubscribed.presence.get { members, error in
                                    expect(error).to(beNil())
                                    guard let members = members else {
                                        fail("Members is nil"); done(); return
                                    }
                                    expect(members).to(haveCount(102)) //100 initial members + "b" + "c", client "a" is discarded
                                    expect(members).to(allPass({ (member: ARTPresenceMessage?) in member!.action != .absent }))
                                    expect(members.filter{ $0.clientId == "a" }).to(beEmpty())
                                    expect(members.filter{ $0.clientId == "b" }).to(haveCount(1))
                                    expect(members.filter{ $0.clientId! == "b" }.first?.timestamp).to(equal(now as Date))
                                    expect(members.filter{ $0.clientId == "c" }).to(haveCount(1))
                                    expect(members.filter{ $0.clientId! == "c" }.first?.timestamp).to(equal(now as Date))
                                    done()
                                }
                            }
                        }
                    }

                    // RTP2b2
                    it("split the id of both presence messages") {
                        let options = AblyTests.commonAppSetup()
                        let now = NSDate()
                        let channelName = NSUUID().uuidString
                        var clientMembers: ARTRealtime?
                        defer { clientMembers?.dispose(); clientMembers?.close() }
                        clientMembers = AblyTests.addMembersSequentiallyToChannel(channelName, members: 101, options: options)

                        let clientSubscribed = AblyTests.newRealtime(options)
                        defer { clientSubscribed.dispose(); clientSubscribed.close() }
                        let channelSubscribed = clientSubscribed.channels.get(channelName)

                        let presenceData: [ARTPresenceMessage] = [
                            ARTPresenceMessage(clientId: "a", action: .enter, connectionId: "one", id: "one:0:0", timestamp: now as Date),
                            ARTPresenceMessage(clientId: "a", action: .leave, connectionId: "one", id: "one:1:0", timestamp: (now as Date) - 1),
                            ARTPresenceMessage(clientId: "b", action: .enter, connectionId: "one", id: "one:2:2", timestamp: now as Date),
                            ARTPresenceMessage(clientId: "b", action: .leave, connectionId: "one", id: "one:2:1", timestamp: (now as Date) + 1),
                            ARTPresenceMessage(clientId: "c", action: .enter, connectionId: "one", id: "one:4:4", timestamp: now as Date),
                            ARTPresenceMessage(clientId: "c", action: .leave, connectionId: "one", id: "one:3:5", timestamp: (now as Date) + 1),
                        ]

                        guard let transport = clientSubscribed.internal.transport as? TestProxyTransport else {
                            fail("TestProxyTransport is not set"); return
                        }

                        waitUntil(timeout: testTimeout) { done in
                            transport.afterProcessingReceivedMessage = { protocolMessage in
                                // Receive the first Sync message from Ably service
                                if protocolMessage.action == .sync {

                                    // Inject a fabricated Presence message
                                    let presenceMessage = ARTProtocolMessage()
                                    presenceMessage.action = .presence
                                    presenceMessage.channel = protocolMessage.channel
                                    presenceMessage.connectionSerial = protocolMessage.connectionSerial + 1
                                    presenceMessage.timestamp = Date()
                                    presenceMessage.presence = presenceData

                                    transport.receive(presenceMessage)

                                    // Simulate an end to the sync
                                    let endSyncMessage = ARTProtocolMessage()
                                    endSyncMessage.action = .sync
                                    endSyncMessage.channel = protocolMessage.channel
                                    endSyncMessage.channelSerial = "validserialprefix:" //with no part after the `:` this indicates the end to the SYNC
                                    endSyncMessage.connectionSerial = protocolMessage.connectionSerial + 2
                                    endSyncMessage.timestamp = Date()

                                    transport.afterProcessingReceivedMessage = nil
                                    transport.receive(endSyncMessage)

                                    // Stop the next sync message from Ably service because we already injected the end of the sync
                                    transport.actionsIgnored = [.sync]

                                    done()
                                }
                            }
                            channelSubscribed.attach()
                        }

                        waitUntil(timeout: testTimeout) { done in
                            channelSubscribed.presence.get { members, error in
                                expect(error).to(beNil())
                                guard let members = members else {
                                    fail("Members is nil"); done(); return
                                }
                                expect(members).to(haveCount(102)) //100 initial members + "b" + "c", client "a" is discarded
                                expect(members).to(allPass({ (member: ARTPresenceMessage?) in member!.action != .absent }))
                                expect(members.filter{ $0.clientId == "a" }).to(beEmpty())
                                expect(members.filter{ $0.clientId == "b" }).to(haveCount(1))
                                expect(members.filter{ $0.clientId! == "b" }.first?.timestamp).to(equal(now as Date))
                                expect(members.filter{ $0.clientId == "c" }).to(haveCount(1))
                                expect(members.filter{ $0.clientId! == "c" }.first?.timestamp).to(equal(now as Date))
                                done()
                            }
                        }
                    }

                }

                // RTP2c
                context("all presence messages from a SYNC must also be compared for newness in the same way as they would from a PRESENCE") {

                    // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
                    xit("discard members where messages have arrived before the SYNC") {
                        let options = AblyTests.commonAppSetup()
                        let timeBeforeSync = NSDate()
                        let channelName = NSUUID().uuidString
                        var clientMembers: ARTRealtime?
                        defer { clientMembers?.dispose(); clientMembers?.close() }
                        clientMembers = AblyTests.addMembersSequentiallyToChannel(channelName, members: 120, options: options)

                        guard let membersConnectionId = clientMembers?.connection.id else {
                            fail("Members client isn't connected"); return
                        }

                        let client = AblyTests.newRealtime(options)
                        defer { client.dispose(); client.close() }
                        let channel = client.channels.get(channelName)

                        guard let transport = client.internal.transport as? TestProxyTransport else {
                            fail("TestProxyTransport is not set"); return
                        }

                        channel.presence.subscribe(.leave) { leave in
                            expect(leave.clientId).to(equal("user110"))
                            fail("Should not fire Leave event for member `user110` because it's out of date")
                        }

                        waitUntil(timeout: testTimeout) { done in
                            let partialDone = AblyTests.splitDone(3, done: done)
                            transport.beforeProcessingReceivedMessage = { protocolMessage in
                                if protocolMessage.action == .sync {
                                    let injectLeave = ARTPresenceMessage()
                                    injectLeave.action = .leave
                                    injectLeave.connectionId = membersConnectionId
                                    injectLeave.clientId = "user110"
                                    injectLeave.timestamp = timeBeforeSync as Date
                                    protocolMessage.presence?.append(injectLeave)
                                    transport.beforeProcessingReceivedMessage = nil
                                    partialDone()
                                }
                            }
                            channel.internal.presenceMap.testSuite_injectIntoMethod(after: #selector(ARTPresenceMap.endSync)) {
                                expect(channel.internal.presenceMap.syncInProgress).to(beFalse())
                                expect(channel.internal.presenceMap.members).to(haveCount(120))
                                expect(channel.internal.presenceMap.members.filter{ _, presence in presence.clientId == "user110" && presence.action == .present }).to(haveCount(1))
                                partialDone()
                            }
                            channel.attach() { error in
                                expect(error).to(beNil())
                                partialDone()
                            }
                        }
                    }

                    // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
                    xit("accept members where message have arrived after the SYNC") {
                        let options = AblyTests.commonAppSetup()
                        let channelName = NSUUID().uuidString
                        var clientMembers: ARTRealtime?
                        defer { clientMembers?.dispose(); clientMembers?.close() }
                        clientMembers = AblyTests.addMembersSequentiallyToChannel(channelName, members: 120, options: options)

                        guard let membersConnectionId = clientMembers?.connection.id else {
                            fail("Members client isn't connected"); return
                        }

                        let client = AblyTests.newRealtime(options)
                        defer { client.dispose(); client.close() }
                        let channel = client.channels.get(channelName)

                        guard let transport = client.internal.transport as? TestProxyTransport else {
                            fail("TestProxyTransport is not set"); return
                        }

                        waitUntil(timeout: testTimeout.multiplied(by: 2)) { done in
                            let partialDone = AblyTests.splitDone(4, done: done)
                            channel.presence.subscribe(.leave) { leave in
                                expect(leave.clientId).to(equal("user110"))
                                partialDone()
                            }
                            transport.beforeProcessingReceivedMessage = { protocolMessage in
                                if protocolMessage.action == .sync {
                                    let injectLeave = ARTPresenceMessage()
                                    injectLeave.action = .leave
                                    injectLeave.connectionId = membersConnectionId
                                    injectLeave.clientId = "user110"
                                    injectLeave.timestamp = (Date()) + 1
                                    protocolMessage.presence?.append(injectLeave)
                                    transport.beforeProcessingReceivedMessage = nil
                                    partialDone()
                                }
                            }
                            channel.internal.presenceMap.testSuite_injectIntoMethod(after: #selector(ARTPresenceMap.endSync)) {
                                expect(channel.internal.presenceMap.syncInProgress).to(beFalse())
                                expect(channel.internal.presenceMap.members).to(haveCount(119))
                                expect(channel.internal.presenceMap.members.filter{ _, presence in presence.clientId == "user110" }).to(beEmpty())
                                partialDone()
                            }
                            channel.attach() { error in
                                expect(error).to(beNil())
                                partialDone()
                            }
                        }
                    }

                }

                // RTP2d
                it("if action of ENTER arrives, it should be added to the presence map with the action set to PRESENT") {
                    let options = AblyTests.commonAppSetup()
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channelName = NSUUID().uuidString
                    let channel = client.channels.get(channelName)

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channel.presence.subscribe(.enter) { _ in
                            partialDone()
                        }
                        channel.presence.enterClient("tester", data: nil) { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                    }

                    expect(channel.internal.presenceMap.members.filter{ _, presence in presence.action == .present }).to(haveCount(1))
                    expect(channel.internal.presenceMap.members.filter{ _, presence in presence.action == .enter }).to(beEmpty())
                }

                // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
                // RTP2d
                xit("if action of UPDATE arrives, it should be added to the presence map with the action set to PRESENT") {
                    let options = AblyTests.commonAppSetup()
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channelName = NSUUID().uuidString
                    let channel = client.channels.get(channelName)

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(3, done: done)
                        channel.presence.subscribe(.update) { _ in
                            partialDone()
                        }
                        channel.presence.enterClient("tester", data: nil) { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                        channel.presence.updateClient("tester", data: nil) { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                    }

                    expect(channel.internal.presenceMap.members).to(haveCount(1))
                    expect(channel.internal.presenceMap.members.filter{ _, presence in presence.action == .present }).to(haveCount(1))
                    expect(channel.internal.presenceMap.members.filter{ _, presence in presence.action == .update }).to(beEmpty())
                }

                // RTP2d
                it("if action of PRESENT arrives, it should be added to the presence map with the action set to PRESENT") {
                    let options = AblyTests.commonAppSetup()
                    let channelName = NSUUID().uuidString
                    var clientMembers: ARTRealtime!
                    defer { clientMembers.dispose(); clientMembers.close() }
                    clientMembers = AblyTests.addMembersSequentiallyToChannel(channelName, members: 1, options: options)

                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get(channelName)

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channel.internal.presenceMap.testSuite_injectIntoMethod(after: #selector(ARTPresenceMap.endSync)) {
                            expect(channel.internal.presenceMap.syncInProgress).to(beFalse())
                            partialDone()
                        }
                        channel.attach() { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                    }

                    expect(channel.internal.presenceMap.members).to(haveCount(1))
                }

                // RTP2e
                xit("if a SYNC is not in progress, then when a presence message with an action of LEAVE arrives, that memberKey should be deleted from the presence map, if present") {
                    let options = AblyTests.commonAppSetup()

                    var clientMembers: ARTRealtime?
                    defer { clientMembers?.dispose(); clientMembers?.close() }
                    let channelName = NSUUID().uuidString
                    clientMembers = AblyTests.addMembersSequentiallyToChannel(channelName, members: 20, options: options)

                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get(channelName)
                    channel.attach()

                    guard let transport = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport is not set"); return
                    }
                    waitUntil(timeout: testTimeout) { done in
                        transport.afterProcessingReceivedMessage = { protocolMessage in
                            if protocolMessage.action == .sync {
                                done()
                            }
                        }
                    }

                    expect(channel.internal.presenceMap.syncInProgress).toEventually(beFalse(), timeout: testTimeout)

                    guard let user11MemberKey = channel.internal.presenceMap.members["\(clientMembers?.connection.id ?? ""):user11"]?.memberKey() else {
                        fail("user11 memberKey is not present"); return
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(.leave) { presence in
                            expect(presence.clientId).to(equal("user11"))
                            done()
                        }
                        clientMembers?.channels.get(channelName).presence.leaveClient("user11", data: nil)
                    }

                    expect(channel.internal.presenceMap.members.filter{ _, presence in presence.memberKey() == user11MemberKey }).to(beEmpty())
                }

                // RTP2f
                xit("if a SYNC is in progress, then when a presence message with an action of LEAVE arrives, it should be stored in the presence map with the action set to ABSENT") {
                    let options = AblyTests.commonAppSetup()
                    let channelName = NSUUID().uuidString

                    var clientMembers: ARTRealtime?
                    defer { clientMembers?.dispose(); clientMembers?.close() }
                    clientMembers = AblyTests.addMembersSequentiallyToChannel(channelName, members: 20, options: options)

                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get(channelName)

                    guard let transport = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport is not set"); return
                    }

                    var hook: AspectToken?
                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        
                        channel.presence.subscribe(.leave) { leave in
                            expect(leave.clientId).to(equal("user11"))
                            partialDone()
                        }

                        hook = channel.internal.presenceMap.testSuite_getArgument(
                            from: #selector(ARTPresenceMap.internalAdd(_:withSessionId:)),
                            at: 0
                        ) { arg in
                            let m = arg as? ARTPresenceMessage
                            if (m?.clientId == "user11" && m?.action == .absent) {
                                partialDone()
                            }
                        }

                        channel.attach { error in
                            expect(error).to(beNil())
                            expect(channel.internal.presenceMap.syncInProgress).to(beTrue())

                            // Inject a fabricated Presence message
                            let leaveMessage = ARTProtocolMessage()
                            leaveMessage.action = .presence
                            leaveMessage.channel = channel.name
                            leaveMessage.connectionSerial = client.connection.internal.serial_nosync() + 1
                            leaveMessage.timestamp = Date()
                            leaveMessage.presence = [
                                ARTPresenceMessage(clientId: "user11", action: .leave, connectionId: "another", id: "another:123:0", timestamp: Date())
                            ]
                            transport.receive(leaveMessage)
                        }
                    }
                    hook?.remove()
                    channel.presence.unsubscribe()
                    
                    expect(channel.internal.presenceMap.syncInProgress).toEventually(beFalse(), timeout: testTimeout)
                    expect(channel.internal.presenceMap.members.filter{ _, presence in presence.action == .leave }).to(beEmpty())
                    expect(channel.internal.presenceMap.members.filter{ _, presence in presence.action == .absent }).to(beEmpty())

                    // A single clientId may be present multiple times on the same channel via different client connections and that's way user11 is present because user11 presences messages were in distinct connections.
                    expect(channel.internal.presenceMap.members).to(haveCount(20))
                }

                // RTP2g
                it("any incoming presence message that passes the newness check should be emitted on the Presence object, with an event name set to its original action") {
                    let options = AblyTests.commonAppSetup()
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channelName = NSUUID().uuidString
                    let channel = client.channels.get(channelName)

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channel.presence.enterClient("tester", data: nil) { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                        channel.presence.subscribe(.enter) { _ in
                            partialDone()
                        }
                    }

                    expect(channel.internal.presenceMap.members.filter{ _, presence in presence.action == .present }).to(haveCount(1))
                    expect(channel.internal.presenceMap.members.filter{ _, presence in presence.action == .enter }).to(beEmpty())
                }

            }

            // RTP8
            context("enter") {
                // RTP8h
                it("should result in an error if the client does not have required presence permission") {
                    let options = AblyTests.commonAppSetup()
                    options.token = getTestToken(clientId: "john", capability: "{ \"cannotpresence:john\":[\"publish\"] }")
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("cannotpresence")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter(nil) { error in
                            guard let error = error else {
                                fail("error expected"); done(); return
                            }
                            expect(error.message).to(contain("Channel denied access based on given capability"))
                            done()
                        }
                    }
                }
            }


            // RTP9
            context("update") {

                // RTP9e
                it("should result in an error immediately if the client is anonymous") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.update(nil) { error in
                            expect(error!.message).to(contain("attempted to publish presence message without clientId"))
                            done()
                        }
                    }
                }

                // RTP9e
                it("should result in an error immediately if the channel is DETACHED") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    channel.attach()
                    channel.detach()
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.detached), timeout: testTimeout)

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.update(nil) { error in
                            expect(error?.code).to(equal(90001))
                            done()
                        }
                    }
                }

                // RTP9e
                it("should result in an error immediately if the channel is FAILED") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    AblyTests.queue.async {
                        channel.internal.onError(AblyTests.newErrorProtocolMessage())
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.update(nil) { error in
                            expect(error?.code).to(equal(90001))
                            done()
                        }
                    }
                }

                // RTP9e
                it("should result in an error if the client does not have required presence permission") {
                    let options = AblyTests.clientOptions()
                    options.token = getTestToken(clientId: "john", capability: "{ \"cannotpresence:john\":[\"publish\"] }")
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("cannotpresence")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.update(nil) { error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error.message).to(contain("Channel denied access based on given capability"))
                            done()
                        }
                    }
                }

                // RTP9e
                it("should result in an error if Ably service determines that the client is unidentified") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.update(nil) { error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error.message).to(contain("presence message without clientId"))
                            done()
                        }
                    }
                }
            }

            // RTP10
            context("leave") {

                // RTP10b
                it("optionally a callback can be provided that is called for success") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter("online") { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.leave("offline") { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }

                // RTP10b
                it("optionally a callback can be provided that is called for failure") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                   waitUntil(timeout: testTimeout) { done in
                       channel.presence.enter("online") { error in
                           expect(error).to(beNil())
                           done()
                       }
                   }

                    waitUntil(timeout: testTimeout) { done in
                        let sentError = ARTErrorInfo.create(withCode: 0, message: "test error")
                        let transport = client.internal.transport as! TestProxyTransport
                        transport.replaceAcksWithNacks(sentError) { doneReplacing in
                            channel.presence.leave("offline") { error in
                                expect(error).to(beIdenticalTo(sentError))
                                doneReplacing()
                                done()
                            }
                        }
                    }
                }

                it("should raise an error if client is not present") {
                    let options = AblyTests.commonAppSetup()
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")
                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.leave("offline") { error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error.code) == Int(ARTState.noClientId.rawValue)
                            expect(error.message).to(contain("message without clientId"))
                            done()
                        }
                    }
                }

                // RTP10c
                it("entering without an explicit PresenceMessage#clientId should implicitly use the clientId of the current connection") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = AblyTests.newRealtime(options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter("online") { error in
                            channel.presence.leave(nil) { error in
                                expect(error).to(beNil())
                                done()
                            }
                        }
                    }

                    let transport = client.internal.transport as! TestProxyTransport

                    let sent = transport.protocolMessagesSent.filter({ $0.action == .presence })[1].presence![0]
                    expect(sent.action).to(equal(ARTPresenceAction.leave))
                    expect(sent.clientId).to(beNil())

                    let receivedPresenceProtocolMessages = transport.protocolMessagesReceived.filter({ $0.action == .presence })
                    let receivedPresenceMessages = receivedPresenceProtocolMessages.flatMap({ $0.presence! })
                    let received = receivedPresenceMessages.filter({ $0.action == .leave })[0]
                    expect(received.action).to(equal(ARTPresenceAction.leave))
                    expect(received.clientId).to(equal("john"))
                }

                // RTP10d
                it("if the client is not currently ENTERED, Ably will respond with an ACK and the request will succeed") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"

                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channelName = NSUUID().uuidString
                    let channel = client.channels.get(channelName)

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.leave(nil) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter("online") { error in
                            expect(error).to(beNil())
                            channel.presence.leave(nil) { error in
                                expect(error).to(beNil())
                                channel.presence.leave(nil) { error in
                                    expect(error).to(beNil())
                                    done()
                                }
                            }
                        }
                    }
                }

            }

            // RTP8
            context("enter") {

                // RTP8d
                it("implicitly attaches the Channel") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"

                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    expect(channel.state).to(equal(ARTRealtimeChannelState.initialized))
                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter("online") { error in
                            expect(error).to(beNil())
                            done()
                        }
                        expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
                    }
                    expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
                }

                // RTP8d
                it("should result in an error if the channel is in the FAILED state") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"

                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    AblyTests.queue.async {
                        channel.internal.onError(AblyTests.newErrorProtocolMessage())
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter("online") { error in
                            expect(error?.code).to(equal(90001))
                            done()
                        }
                    }
                    expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
                }

                // RTP8d
                it("should result in an error if the channel is in the DETACHED state") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"

                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channel.attach { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                        channel.detach { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                    }
                    expect(channel.state).to(equal(ARTRealtimeChannelState.detached))

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter("online") { error in
                            expect(error?.code).to(equal(90001))
                            done()
                        }
                    }
                }

            }

            // RTP10
            context("leave") {

                // RTP10e
                it("should result in an error immediately if the client is anonymous") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.leave(nil) { error in
                            expect(error!.message).to(contain("attempted to publish presence message without clientId"))
                            done()
                        }
                    }
                }

                // RTP10e
                it("should result in an error immediately if the channel is DETACHED") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter(nil) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    channel.detach()

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.leave(nil) { error in
                            expect(error!.message).to(contain("invalid channel state"))
                            done()
                        }
                    }
                }

                // RTP10e
                it("should result in an error immediately if the channel is FAILED") {
                    let options = AblyTests.commonAppSetup()
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enter(nil) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    AblyTests.queue.async {
                        channel.internal.onError(AblyTests.newErrorProtocolMessage())
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.leave(nil) { error in
                            expect(error!.message).to(contain("invalid channel state"))
                            done()
                        }
                    }
                }

                // RTP10e
                it("should result in an error if the client does not have required presence permission") {
                    let options = AblyTests.clientOptions()
                    options.token = getTestToken(clientId: "john", capability: "{ \"cannotpresence:other\":[\"publish\"] }")
                    options.clientId = "john"
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("cannotpresence")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.leaveClient("other", data: nil) { error in
                            expect(error!.message).to(contain("Channel denied access based on given capability"))
                            done()
                        }
                    }
                }

                // RTP10e
                it("should result in an error if Ably service determines that the client is unidentified") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.leave(nil) { error in
                            expect(error!.message).to(contain("presence message without clientId"))
                            done()
                        }
                    }
                }

            }

            // RTP6
            context("subscribe") {

                // RTP6c
                it("should implicitly attach the channel") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    expect(channel.state).to(equal(ARTRealtimeChannelState.initialized))
                    channel.presence.subscribe { _ in }
                    expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

                    channel.detach()
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.detached), timeout: testTimeout)

                    channel.presence.subscribe(.present) { _ in }
                    expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)
                }

                // RTP6c
                it("should result in an error if the channel is in the FAILED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    let protocolError = AblyTests.newErrorProtocolMessage()
                    AblyTests.queue.async {
                        channel.internal.onError(protocolError)
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.subscribe(attachCallback: { error in
                            expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
                            expect(error).toNot(beNil())
                            done()
                        }, callback: { member in
                            fail("Should not be called")
                        })
                    }
                }

                // RTP6c
                it("should result in an error if the channel moves to the FAILED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        let error = AblyTests.newErrorProtocolMessage()
                        channel.presence.subscribe(attachCallback: { error in
                            expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
                            expect(error).toNot(beNil())
                            done()
                        }, callback: { member in
                            fail("Should not be called")
                        })
                        AblyTests.queue.async {
                            channel.internal.onError(error)
                        }
                    }
                }

            }

            // RTP8
            context("enter") {

                // RTP8e
                it("optional data can be included when entering a channel") {
                    let options = AblyTests.commonAppSetup()

                    options.clientId = "john"
                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }
                    let channel1 = client1.channels.get("test")

                    options.clientId = "mary"
                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }
                    let channel2 = client2.channels.get("test")

                    let expectedData = ["data":123]

                    waitUntil(timeout: testTimeout) { done in
                        channel1.attach { error in
                            expect(error).to(beNil())
                            let partlyDone = AblyTests.splitDone(2, done: done)
                            channel1.presence.subscribe(.enter) { member in
                                expect(member.data as? NSObject).to(equal(expectedData as NSObject?))
                                partlyDone()
                            }
                            channel2.presence.enter(expectedData) { error in
                                expect(error).to(beNil())
                                partlyDone()
                            }
                        }
                    }
                }

                // RTP8e
                it("should emit the data attribute in the LEAVE event when data is provided when entering but no data is provided when leaving") {
                    let options = AblyTests.commonAppSetup()

                    options.clientId = "john"
                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }
                    let channel1 = client1.channels.get("test")

                    options.clientId = "mary"
                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }
                    let channel2 = client2.channels.get("test")

                    let expectedData = "data"

                    waitUntil(timeout: testTimeout) { done in
                        channel2.presence.enter(expectedData) { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel1.attach { err in
                            expect(err).to(beNil())
                            let partlyDone = AblyTests.splitDone(2, done: done)
                            channel1.presence.subscribe(.leave) { member in
                                expect(member.data as? NSObject).to(equal(expectedData as NSObject?))
                                partlyDone()
                            }
                            channel2.presence.leave(nil) { error in
                                expect(error).to(beNil())
                                partlyDone()
                            }
                        }
                    }
                }

            }

            // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
            // RTP17
            xcontext("private and internal PresenceMap containing only members that match the current connectionId") {

                it("any ENTER, PRESENT, UPDATE or LEAVE event that matches the current connectionId should be applied to this object") {
                    let options = AblyTests.commonAppSetup()
                    let channelName = NSUUID().uuidString

                    options.clientId = "a"
                    let clientA = ARTRealtime(options: options)
                    defer { clientA.dispose(); clientA.close() }
                    let channelA = clientA.channels.get(channelName)

                    options.clientId = "b"
                    let clientB = ARTRealtime(options: options)
                    defer { clientB.dispose(); clientB.close() }
                    let channelB = clientB.channels.get(channelName)

                    // ENTER
                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channelA.presence.subscribe { presence in
                            guard let currentConnectionId = clientA.connection.id else {
                                fail("ClientA should be connected"); partialDone(); return
                            }
                            expect(presence.action).to(equal(ARTPresenceAction.enter))
                            expect(presence.connectionId).to(equal(currentConnectionId))
                            expect(channelA.internal.presenceMap.members).to(haveCount(1))
                            expect(channelA.internal.presenceMap.localMembers).to(haveCount(1))
                            channelA.presence.unsubscribe()
                            partialDone()
                        }
                        channelB.presence.subscribe { presence in
                            guard let currentConnectionId = clientB.connection.id else {
                                fail("ClientB should be connected"); partialDone(); return
                            }
                            expect(presence.action).to(equal(ARTPresenceAction.enter) || equal(ARTPresenceAction.present))
                            expect(presence.connectionId).toNot(equal(currentConnectionId))
                            expect(channelB.internal.presenceMap.members).to(haveCount(1))
                            expect(channelB.internal.presenceMap.localMembers).to(haveCount(0))
                            channelB.presence.unsubscribe()
                            partialDone()
                        }
                        channelA.presence.enter(nil)
                    }

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channelA.presence.subscribe { presence in
                            guard let currentConnectionId = clientA.connection.id else {
                                fail("ClientA should be connected"); partialDone(); return
                            }
                            expect(presence.action).to(equal(ARTPresenceAction.enter))
                            expect(presence.connectionId).toNot(equal(currentConnectionId))
                            expect(channelA.internal.presenceMap.members).to(haveCount(2))
                            expect(channelA.internal.presenceMap.localMembers).to(haveCount(1))
                            channelA.presence.unsubscribe()
                            partialDone()
                        }
                        channelB.presence.subscribe { presence in
                            guard let currentConnectionId = clientB.connection.id else {
                                fail("ClientB should be connected"); partialDone(); return
                            }
                            expect(presence.action).to(equal(ARTPresenceAction.enter))
                            expect(presence.connectionId).to(equal(currentConnectionId))
                            expect(channelB.internal.presenceMap.members).to(haveCount(2))
                            expect(channelB.internal.presenceMap.localMembers).to(haveCount(1))
                            channelB.presence.unsubscribe()
                            partialDone()
                        }
                        channelB.presence.enter(nil)
                    }

                    // UPDATE
                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channelA.presence.subscribe { presence in
                            guard let currentConnectionId = clientA.connection.id else {
                                fail("ClientA should be connected"); partialDone(); return
                            }
                            expect(presence.action).to(equal(ARTPresenceAction.update))
                            expect(presence.data as? String).to(equal("hello"))
                            expect(presence.connectionId).toNot(equal(currentConnectionId))
                            expect(channelA.internal.presenceMap.members).to(haveCount(2))
                            expect(channelA.internal.presenceMap.localMembers).to(haveCount(1))
                            channelA.presence.unsubscribe()
                            partialDone()
                        }
                        channelB.presence.subscribe { presence in
                            guard let currentConnectionId = clientB.connection.id else {
                                fail("ClientB should be connected"); partialDone(); return
                            }
                            expect(presence.action).to(equal(ARTPresenceAction.update))
                            expect(presence.data as? String).to(equal("hello"))
                            expect(presence.connectionId).to(equal(currentConnectionId))
                            expect(channelB.internal.presenceMap.members).to(haveCount(2))
                            expect(channelB.internal.presenceMap.localMembers).to(haveCount(1))
                            channelB.presence.unsubscribe()
                            partialDone()
                        }
                        channelB.presence.update("hello")
                    }

                    // LEAVE
                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channelA.presence.subscribe { presence in
                            guard let currentConnectionId = clientA.connection.id else {
                                fail("ClientA should be connected"); partialDone(); return
                            }
                            expect(presence.action).to(equal(ARTPresenceAction.leave))
                            expect(presence.data as? String).to(equal("bye"))
                            expect(presence.connectionId).toNot(equal(currentConnectionId))
                            expect(channelA.internal.presenceMap.members).to(haveCount(1))
                            expect(channelA.internal.presenceMap.localMembers).to(haveCount(1))
                            channelA.presence.unsubscribe()
                            partialDone()
                        }
                        channelB.presence.subscribe { presence in
                            guard let currentConnectionId = clientB.connection.id else {
                                fail("ClientB should be connected"); partialDone(); return
                            }
                            expect(presence.action).to(equal(ARTPresenceAction.leave))
                            expect(presence.data as? String).to(equal("bye"))
                            expect(presence.connectionId).to(equal(currentConnectionId))
                            expect(channelB.internal.presenceMap.members).to(haveCount(1))
                            expect(channelB.internal.presenceMap.localMembers).to(haveCount(0))
                            channelB.presence.unsubscribe()
                            partialDone()
                        }
                        channelB.presence.leave("bye")
                    }
                }

                // RTP17a
                it("all members belonging to the current connection are published as a PresenceMessage on the Channel by the server irrespective of whether the client has permission to subscribe or the Channel is configured to publish presence events") {
                    let options = AblyTests.commonAppSetup()
                    let channelName = NSUUID().uuidString
                    let clientId = NSUUID().uuidString
                    options.tokenDetails = getTestTokenDetails(clientId: clientId, capability: "{\"\(channelName)\":[\"presence\",\"publish\"]}")
                    // Prevent channel name to be prefixed by test-*
                    options.channelNamePrefix = nil
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get(channelName)
                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channel.presence.enterClient(clientId, data: nil) { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                        channel.presence.subscribe(.enter) { presence in
                            expect(presence.clientId).to(equal(clientId))
                            partialDone()
                        }
                    }
                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get { members, error in
                            expect(error).to(beNil())
                            expect(members).to(haveCount(1))
                            expect(channel.internal.presenceMap.members).to(haveCount(1))
                            expect(channel.internal.presenceMap.localMembers).to(haveCount(1))
                            done()
                        }
                    }
                }

                // RTP17b
                context("events applied to presence map") {

                    xit("should be applied to ENTER, PRESENT or UPDATE events with a connectionId that matches the current client’s connectionId") {
                        let options = AblyTests.commonAppSetup()
                        let client = ARTRealtime(options: options)
                        defer { client.dispose(); client.close() }

                        let channel = client.channels.get("foo")
                        waitUntil(timeout: testTimeout) { done in
                            let partialDone = AblyTests.splitDone(2, done: done)
                            channel.presence.subscribe(.enter) { presence in
                                expect(presence.clientId).to(equal("one"))
                                channel.presence.unsubscribe()
                                partialDone()
                            }
                            channel.presence.enterClient("one", data: nil) { error in
                                expect(error).to(beNil())
                                partialDone()
                            }
                        }

                        guard let connectionId = client.connection.id else {
                            fail("connectionId is empty"); return
                        }

                        expect(channel.internal.presenceMap.localMembers).to(haveCount(1))

                        let additionalMember = ARTPresenceMessage(
                            clientId: "two",
                            action: .enter,
                            connectionId: connectionId,
                            id: connectionId + ":0:0"
                        )

                        // Inject an additional member into the myMember set, then force a suspended state
                        client.simulateSuspended(beforeSuspension: { done in
                            channel.internal.presenceMap.localMembers.add(additionalMember)
                            done()
                        })
                        expect(client.connection.state).toEventually(equal(.suspended), timeout: testTimeout)

                        expect(channel.internal.presenceMap.localMembers).to(haveCount(2))

                        waitUntil(timeout: testTimeout) { done in
                            let partialDone = AblyTests.splitDone(2, done: done)
                            channel.once(.attached) { stateChange in
                                expect(stateChange?.reason).to(beNil())
                                partialDone()
                            }
                            // Reconnect
                            client.connect()
                            // Await Sync
                            channel.internal.presenceMap.onceSyncEnds { _ in
                                partialDone()
                            }
                        }

                        expect(channel.internal.presenceMap.syncComplete).toEventually(beTrue(), timeout: testTimeout)

                        // Should remove the "two" member that was added manually because the connectionId
                        //doesn't match and it's not synthesized, it will be re-entered.
                        expect(channel.internal.presenceMap.localMembers).to(haveCount(1))

                        waitUntil(timeout: testTimeout) { done in
                            let partialDone = AblyTests.splitDone(2, done: done)
                            channel.presence.subscribe(.enter) { presence in
                                expect(presence.clientId).to(equal("two"))
                                channel.presence.unsubscribe()
                                partialDone()
                            }
                            if channel.internal.presenceMap.syncComplete {
                                channel.internal.sync { error in
                                    expect(error).to(beNil())
                                    channel.internal.presenceMap.onceSyncEnds { _ in
                                        partialDone()
                                    }
                                }
                            }
                        }

                        waitUntil(timeout: testTimeout) { done in
                            channel.presence.get { presences, error in
                                expect(error).to(beNil())
                                guard let presences = presences else {
                                    fail("Presences is nil"); done(); return
                                }
                                expect(channel.internal.presenceMap.syncComplete).to(beTrue())
                                expect(presences).to(haveCount(2))
                                expect(presences.map({$0.clientId})).to(contain(["one", "two"]))
                                done()
                            }
                        }
                    }

                    it("should be applied to any LEAVE event with a connectionId that matches the current client’s connectionId and is not a synthesized") {
                        let options = AblyTests.commonAppSetup()
                        let client = ARTRealtime(options: options)
                        client.internal.shouldImmediatelyReconnect = false
                        defer { client.dispose(); client.close() }

                        let channel = client.channels.get("foo")
                        waitUntil(timeout: testTimeout) { done in
                            let partialDone = AblyTests.splitDone(2, done: done)
                            channel.presence.subscribe(.enter) { presence in
                                expect(presence.clientId).to(equal("one"))
                                channel.presence.unsubscribe()
                                partialDone()
                            }
                            channel.presence.enterClient("one", data: nil) { error in
                                expect(error).to(beNil())
                                partialDone()
                            }
                        }

                        waitUntil(timeout: DispatchTimeInterval.seconds(20)) { done in
                            channel.internal.presenceMap.onceSyncEnds { _ in
                                // Synthesized leave
                                expect(channel.internal.presenceMap.localMembers).to(beEmpty())
                                done()
                            }
                            client.internal.onDisconnected()
                        }

                        waitUntil(timeout: testTimeout) { done in
                            channel.presence.subscribe(.enter) { presence in
                                // Re-entering...
                                expect(presence.clientId).to(equal("one"))
                                channel.presence.unsubscribe()
                                done()
                            }
                        }

                        waitUntil(timeout: testTimeout) { done in
                            channel.presence.get { presences, error in
                                expect(error).to(beNil())
                                guard let presences = presences else {
                                    fail("Presences is nil"); done(); return
                                }
                                expect(channel.internal.presenceMap.syncComplete).to(beTrue())
                                expect(presences).to(haveCount(1))
                                expect(presences.map({$0.clientId})).to(contain(["one"]))
                                done()
                            }
                        }
                    }

                }

            }

            // RTP15d
            it("callback can be provided that will be called upon success") {
                let options = AblyTests.commonAppSetup()
                let client = ARTRealtime(options: options)
                defer { client.dispose(); client.close() }
                let channel = client.channels.get("room")

                waitUntil(timeout: testTimeout) { done in
                    channel.presence.enterClient("Client 1", data: nil) { errorInfo in
                        expect(errorInfo).to(beNil())
                        done()
                    }
                }
            }

            // RTP15d
            it("callback can be provided that will be called upon failure") {
                let options = AblyTests.clientOptions()
                options.token = getTestToken(capability: "{ \"room\":[\"subscribe\"] }")
                let client = ARTRealtime(options: options)
                defer { client.dispose(); client.close() }
                let channel = client.channels.get("private-room")

                waitUntil(timeout: testTimeout) { done in
                    channel.presence.enterClient("Client 1", data: nil) { errorInfo in
                        guard let errorInfo = errorInfo else {
                            fail("ErrorInfo is empty"); done()
                            return
                        }
                        expect(errorInfo.code).to(equal(40160))
                        done()
                    }
                }
            }

            // RTP15c
            it("should also ensure that using updateClient has no side effects on a client that has entered normally using Presence#enter") {
                let options = AblyTests.commonAppSetup()
                options.clientId = "john"
                let client = ARTRealtime(options: options)
                defer { client.dispose(); client.close() }
                let channel = client.channels.get("test")

                waitUntil(timeout: testTimeout) { done in
                    channel.presence.enter(nil) { error in
                        expect(error).to(beNil())
                        channel.presence.updateClient("john", data:"mobile") { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }
                }

                waitUntil(timeout: testTimeout) { done in
                    channel.presence.get() { members, error in
                        expect(members!.first!.data as? String).to(equal("mobile"))
                        done()
                    }
                }
            }

            // RTP15e
            let cases: [String:(ARTRealtimePresence, Optional<(ARTErrorInfo?)->Void>)->()] = [
                "enterClient": { $0.enterClient("john", data: nil, callback: $1) },
                "updateClient": { $0.updateClient("john", data: nil, callback: $1) },
                "leaveClient": { $0.leaveClient("john", data: nil, callback: $1) }
            ]
            for (testCase, performMethod) in cases {
                context(testCase) {
                    it("should implicitly attach the Channel") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.dispose(); client.close() }
                        let channel = client.channels.get("test")

                        expect(channel.state).to(equal(ARTRealtimeChannelState.initialized))
                        waitUntil(timeout: testTimeout) { done in
                            //Call: enterClient, updateClient and leaveClient
                            performMethod(channel.presence) { errorInfo in
                                expect(errorInfo).to(beNil())
                                done()
                            }
                            expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
                        }
                        expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
                    }

                    it("should result in an error if the channel is in the FAILED state") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.dispose(); client.close() }
                        let channel = client.channels.get("test")

                        let expectedErrorMessage = "Something has failed"
                        AblyTests.queue.async {
                            channel.internal.onError(AblyTests.newErrorProtocolMessage(message: expectedErrorMessage))
                        }

                        waitUntil(timeout: testTimeout) { done in
                            //Call: enterClient, updateClient and leaveClient
                            performMethod(channel.presence) { error in
                                expect(error?.code).to(equal(90001))
                                expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
                                guard let reason = channel.errorReason else {
                                    fail("Reason is empty"); done(); return
                                }
                                expect(reason.message).to(equal(expectedErrorMessage))
                                done()
                            }
                        }
                    }

                    it("should result in an error if the channel moves to the FAILED state") {
                        let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
                        defer { client.dispose(); client.close() }
                        let channel = client.channels.get("test")

                        waitUntil(timeout: testTimeout) { done in
                            let error = AblyTests.newErrorProtocolMessage()
                            channel.once(.attaching) { _ in
                                AblyTests.queue.async {
                                    channel.internal.onError(error)
                                }
                            }
                            (client.internal.transport as! TestProxyTransport).actionsIgnored += [.attached]
                            //Call: enterClient, updateClient and leaveClient
                            performMethod(channel.presence) { errorInfo in
                                expect(errorInfo).to(equal(error.error))
                                done()
                            }
                        }
                    }
                }
            }

            // RTP15f
            it("should indicate an error if the client is identified and has a valid clientId and the clientId argument does not match the client’s clientId") {
                let options = AblyTests.commonAppSetup()
                options.clientId = "john"
                let client = ARTRealtime(options: options)
                defer { client.dispose(); client.close() }
                let channel = client.channels.get("test")

                waitUntil(timeout: testTimeout) { done in
                    channel.presence.enter("browser") { error in
                        expect(error).to(beNil())
                        channel.presence.updateClient("tester", data:"mobile") { error in
                            expect(error!.message).to(contain("mismatched clientId"))
                            done()
                        }
                    }
                }

                waitUntil(timeout: testTimeout) { done in
                    channel.presence.get() { members, error in
                        expect(members?.first?.data as? String).to(equal("browser"))
                        done()
                    }
                }
            }

            // RTP16
            context("Connection state conditions") {

                // RTP16a
                it("all presence messages are published immediately if the connection is CONNECTED") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enterClient("user", data: nil) { error in
                            expect(error).to(beNil())
                            expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                            expect(client.internal.queuedMessages).to(haveCount(0))
                            done()
                        }
                        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connecting))
                        expect(client.internal.queuedMessages).to(haveCount(1))
                    }
                }

                // RTP16b
                it("all presence messages will be queued and delivered as soon as the connection state returns to CONNECTED") {
                    let options = AblyTests.commonAppSetup()
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")
                    expect(client.internal.options.queueMessages).to(beTrue())

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach() { _ in
                            client.internal.onDisconnected()
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enterClient("user", data: nil) { error in
                            expect(error).to(beNil())
                            expect(client.connection.state).to(equal(ARTRealtimeConnectionState.connected))
                            expect(client.internal.queuedMessages).to(haveCount(0))
                            done()
                        }
                        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.disconnected))
                        expect(client.internal.queuedMessages).to(haveCount(1))
                    }
                }

                // RTP16b
                it("all presence messages will be lost if queueMessages has been explicitly set to false") {
                    let options = AblyTests.commonAppSetup()
                    options.queueMessages = false
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")
                    expect(client.internal.options.queueMessages).to(beFalse())

                    expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach() { _ in
                            client.internal.onDisconnected()
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enterClient("user", data: nil) { error in
                            expect(error).toNot(beNil())
                            done()
                        }
                        expect(client.internal.queuedMessages).to(haveCount(0))
                    }
                }

                // RTP16c
                it("should result in an error if the connection state is INITIALIZED and queueMessages has been explicitly set to false") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    options.queueMessages = false
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    expect(client.connection.state).to(equal(ARTRealtimeConnectionState.initialized))

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enterClient("user", data: nil) { error in
                            expect(error?.code).to(equal(80010))
                            expect(channel.presence.internal.pendingPresence).to(haveCount(0))
                            done()
                        }
                        expect(channel.presence.internal.pendingPresence).to(haveCount(0))
                    }
                }

                // RTP16c
                let cases: [ARTRealtimeConnectionState:(ARTRealtime)->()] = [
                    .suspended: { client in
                        AblyTests.queue.async {
                            client.internal.onSuspended()
                        }
                    },
                    .closed: { client in
                        client.close()
                    },
                    .failed: { client in
                        AblyTests.queue.async {
                            client.internal.onError(AblyTests.newErrorProtocolMessage())
                        }
                    }
                ]
                for (connectionState, performMethod) in cases {
                    it("should result in an error if the connection state is \(connectionState)") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.dispose(); client.close() }
                        let channel = client.channels.get("test")
                        expect(client.internal.options.queueMessages).to(beTrue())

                        waitUntil(timeout: testTimeout) { done in
                            channel.attach() { _ in
                                performMethod(client)
                                done()
                            }
                        }

                        expect(client.connection.state).toEventually(equal(connectionState), timeout: testTimeout)

                        waitUntil(timeout: testTimeout) { done in
                            channel.presence.enterClient("user", data: nil) { error in
                                expect(error).toNot(beNil())
                                expect(client.internal.queuedMessages).to(haveCount(0))
                                done()
                            }
                            expect(client.internal.queuedMessages).to(haveCount(0))
                        }
                    }
                }

            }

            // RTP11
            context("get") {

                context("query") {
                    it("waitForSync should be true by default") {
                        expect(ARTRealtimePresenceQuery().waitForSync).to(beTrue())
                    }
                }
                
                // FIXME Fix flaky presence tests and re-enable. See https://ably-real-time.slack.com/archives/C030C5YLY/p1623172436085700
                // RTP11a
                xit("should return a list of current members on the channel") {
                    let options = AblyTests.commonAppSetup()

                    var disposable = [ARTRealtime]()
                    defer {
                        for clientItem in disposable {
                            clientItem.dispose()
                            clientItem.close()
                        }
                    }

                    let expectedData = "online"

                    disposable += [AblyTests.addMembersSequentiallyToChannel("test", members: 150, data:expectedData as AnyObject?, options: options)]

                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    var presenceQueryWasCreated = false
                    let hook = ARTRealtimePresenceQuery.testSuite_injectIntoClassMethod(#selector(ARTRealtimePresenceQuery.init as () -> ARTRealtimePresenceQuery)) { // Default initialiser: referring to the no-parameter variant of `init` as one of several overloaded methods requires an explicit `as <signature>` cast
                        presenceQueryWasCreated = true
                    }
                    defer { hook?.remove() }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get { members, error in
                            expect(error).to(beNil())
                            expect(members).to(haveCount(150))
                            expect(members!.first).to(beAnInstanceOf(ARTPresenceMessage.self))
                            expect(members).to(allPass({ member in
                                return NSRegularExpression.match(member!.clientId, pattern: "^user(\\d+)$")
                                    && (member!.data as? String) == expectedData
                            }))
                            done()
                        }
                    }

                    expect(presenceQueryWasCreated).to(beTrue())
                }

                // RTP11b
                it("should implicitly attach the channel") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    expect(channel.state).to(equal(ARTRealtimeChannelState.initialized))
                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get() { membersPage, error in
                            expect(error).to(beNil())
                            expect(membersPage).toNot(beNil())
                            done()
                        }
                        expect(channel.state).to(equal(ARTRealtimeChannelState.attaching))
                    }
                    expect(channel.state).to(equal(ARTRealtimeChannelState.attached))
                }

                // RTP11b
                it("should result in an error if the channel is in the FAILED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    let pm = AblyTests.newErrorProtocolMessage()
                    AblyTests.queue.async {
                        channel.internal.onError(pm)
                    }

                    guard let protocolError = pm.error else {
                        fail("Protocol error is empty"); return
                    }
                    guard let channelError = channel.errorReason else {
                        fail("Channel error is empty"); return
                    }
                    expect(channelError.message).to(equal(protocolError.message))
                    expect(channel.state).to(equal(ARTRealtimeChannelState.failed))

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get() { members, error in
                            expect(error?.code).to(equal(90001))
                            expect(channel.errorReason).to(equal(protocolError))
                            expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
                            expect(members).to(beNil())
                            done()
                        }
                    }
                }

                // RTP11b
                it("should result in an error if the channel moves to the FAILED state") {
                    let client = AblyTests.newRealtime(AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        let pm = AblyTests.newErrorProtocolMessage()
                        guard let protocolError = pm.error else {
                            fail("Protocol error is empty"); done(); return
                        }
                        (client.internal.transport as! TestProxyTransport).actionsIgnored += [.attached]
                        channel.once(.attaching) { _ in
                            AblyTests.queue.async {
                                channel.internal.onError(pm)
                            }
                        }
                        channel.presence.get() { members, error in
                            guard let error = error else {
                                fail("Error is empty"); done(); return
                            }
                            expect(error.message).to(equal(protocolError.message))
                            expect(members).to(beNil())
                            done()
                        }
                    }

                    expect(channel.state).to(equal(ARTRealtimeChannelState.failed))
                }

                // RTP11b
                it("should result in an error if the channel is in the DETACHED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach()
                        channel.detach() { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get() { members, error in
                            expect(error?.code).to(equal(90001))
                            expect(members).to(beNil())
                            expect(channel.state).to(equal(ARTRealtimeChannelState.detached))
                            done()
                        }
                    }
                }

                // RTP11b
                it("should result in an error if the channel moves to the DETACHED state") {
                    let options = AblyTests.commonAppSetup()

                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }

                    var clientMembers: ARTRealtime?
                    defer { clientMembers?.dispose(); clientMembers?.close() }
                    clientMembers = AblyTests.addMembersSequentiallyToChannel("test", members: 120, options: options)

                    let channel = client.channels.get("test")
                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(2, done: done)
                        channel.presence.get() { members, error in
                            guard let error = error else {
                                fail("Error is nil"); done(); return
                            }
                            expect(error.message).to(equal("channel is being DETACHED"))
                            expect(members).to(beNil())
                            partialDone()
                        }
                        channel.detach() { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                    }

                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.detached), timeout: testTimeout)
                }
                
                // RTP11d
                context("If the Channel is in the SUSPENDED state then") {
                    func getSuspendedChannel() -> (ARTRealtimeChannel, ARTRealtime) {
                        let options = AblyTests.commonAppSetup()
                        
                        let client = ARTRealtime(options: options)
                        let channel = client.channels.get("test")
                        
                        waitUntil(timeout: testTimeout) { done in
                            channel.once(.suspended) { _ in
                                done()
                            }
                            client.internal.onSuspended()
                        }
                        
                        return (channel, client)
                    }

                    for (name, getPresence) in [
                        ("by default", { channel, callback in
                            channel.presence.get(callback)
                        }),
                        ("if waitForSync is true", { channel, callback in
                            let params = ARTRealtimePresenceQuery()
                            params.waitForSync = true
                            channel.presence.get(params, callback: callback)
                        })
                    ] as [(String, (ARTRealtimeChannel, @escaping ([ARTPresenceMessage]?, ARTErrorInfo?) -> Void) -> Void)] {
                        context(name) {
                            it("results in an error") {
                                let (channel, client) = getSuspendedChannel()
                                defer { client.dispose(); client.close() }
                                
                                getPresence(channel) { result, err in
                                    expect(result).to(beNil())
                                    expect(err).toNot(beNil())
                                    guard let err = err else {
                                        return
                                    }
                                    expect(err.code).to(equal(91005))
                                }
                            }
                        }
                    }
                    
                    context("if waitForSync is false") {
                        let getParams = ARTRealtimePresenceQuery()
                        getParams.waitForSync = false
                        
                        it("returns the members in the current PresenceMap") {
                            let (channel, client) = getSuspendedChannel()
                            defer { client.dispose(); client.close() }
                            
                            var msgs = [String: ARTPresenceMessage]()
                            for i in 0..<3 {
                                let msg = ARTPresenceMessage(clientId: "client\(i)", action: .present, connectionId: "foo", id: "foo:0:0")
                                msgs[msg.clientId!] = msg
                                channel.internal.presenceMap.internalAdd(msg)
                            }
                            
                            channel.presence.get(getParams) { result, err in
                                expect(err).to(beNil())
                                expect(result).toNot(beNil())
                                guard let result = result else {
                                    return
                                }
                                var resultByClient = [String: ARTPresenceMessage]()
                                for msg in result {
                                    resultByClient[msg.clientId ?? "(no clientId)"] = msg
                                }
                                expect(resultByClient).to(equal(msgs))
                            }
                        }
                    }
                }

                // RTP11c
                context("Query (set of params)") {

                    // RTP11c1
                    it("waitForSync is true, should wait until SYNC is complete before returning a list of members") {
                        let options = AblyTests.commonAppSetup()
                        var clientSecondary: ARTRealtime!
                        defer { clientSecondary.dispose(); clientSecondary.close() }
                        clientSecondary = AblyTests.addMembersSequentiallyToChannel("test", members: 150, options: options)

                        let client = AblyTests.newRealtime(options)
                        defer { client.dispose(); client.close() }
                        let channel = client.channels.get("test")

                        let query = ARTRealtimePresenceQuery()
                        expect(query.waitForSync).to(beTrue())

                        waitUntil(timeout: testTimeout) { done in
                            channel.attach() { error in
                                expect(error).to(beNil())
                                let transport = client.internal.transport as! TestProxyTransport
                                transport.beforeProcessingReceivedMessage = { protocolMessage in
                                    if protocolMessage.action == .sync {
                                        expect(protocolMessage.presence!.count).to(equal(100))
                                        channel.presence.get(query) { members, error in
                                            expect(error).to(beNil())
                                            expect(members).to(haveCount(150))
                                            done()
                                        }
                                        transport.beforeProcessingReceivedMessage = nil
                                    }
                                }
                            }
                        }
                    }

                    // RTP11c1
                    it("waitForSync is false, should return immediately the known set of presence members") {
                        let options = AblyTests.commonAppSetup()
                        var clientSecondary: ARTRealtime!
                        defer { clientSecondary.dispose(); clientSecondary.close() }
                        clientSecondary = AblyTests.addMembersSequentiallyToChannel("test", members: 150, options: options)

                        let client = AblyTests.newRealtime(options)
                        defer { client.dispose(); client.close() }
                        let channel = client.channels.get("test")

                        let query = ARTRealtimePresenceQuery()
                        query.waitForSync = false

                        waitUntil(timeout: testTimeout) { done in
                            channel.attach() { error in
                                expect(error).to(beNil())
                                let transport = client.internal.transport as! TestProxyTransport
                                transport.beforeProcessingReceivedMessage = { message in
                                    if message.action == .sync {
                                        // Ignore next SYNC so that the sync process never finishes.
                                        transport.actionsIgnored += [.sync]
                                        done()
                                    }
                                }
                            }
                        }
                        
                        waitUntil(timeout: testTimeout) { done in
                            channel.presence.get(query) { members, error in
                                expect(error).to(beNil())
                                expect(members).to(haveCount(100))
                                done()
                            }
                        }
                    }

                    // RTP11c2
                    it("should return members filtered by clientId") {
                        let options = AblyTests.commonAppSetup()
                        let now = NSDate()

                        let client = AblyTests.newRealtime(options)
                        defer { client.dispose(); client.close() }
                        let channelName = NSUUID().uuidString
                        let channel = client.channels.get(channelName)

                        let presenceData: [ARTPresenceMessage] = [
                            ARTPresenceMessage(clientId: "a", action: .enter, connectionId: "one", id: "one:0:0", timestamp: now as Date),
                            ARTPresenceMessage(clientId: "a", action: .leave, connectionId: "one", id: "fabricated:0:1", timestamp: (now as Date) + 1),
                            ARTPresenceMessage(clientId: "b", action: .enter, connectionId: "one", id: "one:0:2", timestamp: now as Date),
                            ARTPresenceMessage(clientId: "b", action: .leave, connectionId: "one", id: "fabricated:0:3", timestamp: (now as Date) - 1),
                            ARTPresenceMessage(clientId: "c", action: .enter, connectionId: "one", id: "fabricated:0:4", timestamp: now as Date),
                            ARTPresenceMessage(clientId: "c", action: .leave, connectionId: "one", id: "fabricated:0:5", timestamp: (now as Date) - 1),
                        ]

                        guard let transport = client.internal.transport as? TestProxyTransport else {
                            fail("TestProxyTransport is not set"); return
                        }

                        waitUntil(timeout: testTimeout) { done in
                            channel.attach() { error in
                                expect(error).to(beNil())

                                // Inject a fabricated Presence message
                                let presenceMessage = ARTProtocolMessage()
                                presenceMessage.action = .presence
                                presenceMessage.channel = channel.name
                                presenceMessage.timestamp = Date()
                                presenceMessage.presence = presenceData

                                transport.receive(presenceMessage)

                                done()
                            }
                        }

                        let query = ARTRealtimePresenceQuery()
                        query.clientId = "b"

                        waitUntil(timeout: testTimeout) { done in
                            channel.presence.get(query) { members, error in
                                expect(error).to(beNil())
                                guard let members = members else {
                                    fail("Members is nil"); done(); return
                                }
                                expect(members).to(haveCount(1))
                                expect(members).to(allPass({ (member: ARTPresenceMessage?) in member!.action != .absent }))
                                expect(members.filter{ $0.clientId == "a" }).to(beEmpty())
                                expect(members.filter{ $0.clientId == "b" }).to(haveCount(1))
                                expect(members.filter{ $0.clientId == "c" }).to(beEmpty())
                                done()
                            }
                        }
                    }

                    // RTP11c3
                    it("should return members filtered by connectionId") {
                        let options = AblyTests.commonAppSetup()
                        let now = NSDate()
                        let channelName = NSUUID().uuidString
                        var clientMembers: ARTRealtime?
                        defer { clientMembers?.dispose(); clientMembers?.close() }
                        clientMembers = AblyTests.addMembersSequentiallyToChannel(channelName, members: 101, options: options)

                        let clientSubscribed = AblyTests.newRealtime(options)
                        defer { clientSubscribed.dispose(); clientSubscribed.close() }
                        let channelSubscribed = clientSubscribed.channels.get(channelName)

                        let presenceData: [ARTPresenceMessage] = [
                            ARTPresenceMessage(clientId: "a", action: .enter, connectionId: "one", id: "one:0:0", timestamp: now as Date),
                            ARTPresenceMessage(clientId: "a", action: .leave, connectionId: "one", id: "fabricated:0:1", timestamp: (now as Date) + 1),
                            ARTPresenceMessage(clientId: "b", action: .enter, connectionId: "one", id: "one:0:2", timestamp: now as Date),
                            ARTPresenceMessage(clientId: "b", action: .leave, connectionId: "one", id: "fabricated:0:3", timestamp: (now as Date) - 1),
                            ARTPresenceMessage(clientId: "c", action: .enter, connectionId: "one", id: "fabricated:0:4", timestamp: now as Date),
                            ARTPresenceMessage(clientId: "c", action: .leave, connectionId: "one", id: "fabricated:0:5", timestamp: (now as Date) - 1),
                        ]

                        guard let transport = clientSubscribed.internal.transport as? TestProxyTransport else {
                            fail("TestProxyTransport is not set"); return
                        }

                        waitUntil(timeout: testTimeout) { done in
                            transport.afterProcessingReceivedMessage = { protocolMessage in
                                // Receive the first Sync message from Ably service
                                if protocolMessage.action == .sync {

                                    // Inject a fabricated Presence message
                                    let presenceMessage = ARTProtocolMessage()
                                    presenceMessage.action = .presence
                                    presenceMessage.channel = protocolMessage.channel
                                    presenceMessage.connectionSerial = protocolMessage.connectionSerial + 1
                                    presenceMessage.timestamp = Date()
                                    presenceMessage.presence = presenceData

                                    transport.receive(presenceMessage)

                                    // Simulate an end to the sync
                                    let endSyncMessage = ARTProtocolMessage()
                                    endSyncMessage.action = .sync
                                    endSyncMessage.channel = protocolMessage.channel
                                    endSyncMessage.channelSerial = "validserialprefix:" //with no part after the `:` this indicates the end to the SYNC
                                    endSyncMessage.connectionSerial = protocolMessage.connectionSerial + 2
                                    endSyncMessage.timestamp = Date()

                                    transport.afterProcessingReceivedMessage = nil
                                    transport.receive(endSyncMessage)

                                    // Stop the next sync message from Ably service because we already injected the end of the sync
                                    transport.actionsIgnored = [.sync]

                                    done()
                                }
                            }
                            channelSubscribed.attach()
                        }

                        let query = ARTRealtimePresenceQuery()
                        query.connectionId = "one"

                        waitUntil(timeout: testTimeout) { done in
                            channelSubscribed.presence.get(query) { members, error in
                                expect(error).to(beNil())
                                guard let members = members else {
                                    fail("Members is nil"); done(); return
                                }
                                expect(members).to(haveCount(2))
                                expect(members).to(allPass({ (member: ARTPresenceMessage?) in member!.action != .absent }))
                                expect(members.filter{ $0.clientId == "a" }).to(beEmpty())
                                expect(members.filter{ $0.clientId == "b" }).to(haveCount(1))
                                expect(members.filter{ $0.clientId == "c" }).to(haveCount(1))
                                done()
                            }
                        }
                    }

                }

            }

            // RTP12
            context("history") {

                // RTP12a
                it("should support all the same params as Rest") {
                    let options = AblyTests.commonAppSetup()

                    let rest = ARTRest(options: options)

                    let realtime = ARTRealtime(options: options)
                    defer { realtime.dispose(); realtime.close() }

                    let channelRest = rest.channels.get("test")
                    let channelRealtime = realtime.channels.get("test")

                    var restPresenceHistoryMethodWasCalled = false

                    let hookRest = channelRest.presence.internal.testSuite_injectIntoMethod(after: #selector(ARTRestPresenceInternal.history(_:callback:))) {
                        restPresenceHistoryMethodWasCalled = true
                    }
                    defer { hookRest.remove() }

                    let hookRealtime = channelRealtime.presence.internal.testSuite_injectIntoMethod(after: #selector(ARTRestPresenceInternal.history(_:callback:))) {
                        restPresenceHistoryMethodWasCalled = true
                    }
                    defer { hookRealtime.remove() }

                    let queryRealtime = ARTRealtimeHistoryQuery()
                    queryRealtime.start = Date()
                    queryRealtime.end = Date()
                    queryRealtime.direction = .forwards
                    queryRealtime.limit = 50

                    let queryRest = queryRealtime as ARTDataQuery

                    waitUntil(timeout: testTimeout) { done in
                        expect {
                            try channelRest.presence.history(queryRest) { _, _ in
                                done()
                            }
                        }.toNot(throwError() { err in fail("\(err)"); done() })
                    }
                    expect(restPresenceHistoryMethodWasCalled).to(beTrue())
                    restPresenceHistoryMethodWasCalled = false

                    waitUntil(timeout: testTimeout) { done in
                        expect {
                            try channelRealtime.presence.history(queryRealtime) { _, _ in
                                done()
                            }
                        }.toNot(throwError() { err in fail("\(err)"); done() })
                    }
                    expect(restPresenceHistoryMethodWasCalled).to(beTrue())
                }

            }

            // RTP12
            context("history") {

                // RTP12c, RTP12d
                xit("should return a PaginatedResult page") {
                    let options = AblyTests.commonAppSetup()

                    var clientSecondary: ARTRealtime!
                    defer { clientSecondary.dispose(); clientSecondary.close() }

                    let expectedData = ["x", "y"]
                    let expectedPattern = "^user(\\d+)$"
                    clientSecondary = AblyTests.addMembersSequentiallyToChannel("test", members: 150, data: expectedData as AnyObject?, options: options)

                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.history { membersPage, error in
                            expect(error).to(beNil())
                            guard let membersPage = membersPage else {
                                fail("membersPage is empty"); done(); return
                            }
                            expect(membersPage).to(beAnInstanceOf(ARTPaginatedResult<ARTPresenceMessage>.self))
                            expect(membersPage.items).to(haveCount(100))

                            let members = membersPage.items 
                            expect(members).to(allPass({ member in
                                return NSRegularExpression.match(member!.clientId, pattern: expectedPattern)
                                    && (member!.data as! [String]) == expectedData
                            }))

                            expect(membersPage.hasNext).to(beTrue())
                            expect(membersPage.isLast).to(beFalse())

                            membersPage.next { nextPage, error in
                                expect(error).to(beNil())
                                guard let nextPage = nextPage else {
                                    fail("nextPage is empty"); done(); return
                                }
                                expect(nextPage).to(beAnInstanceOf(ARTPaginatedResult<ARTPresenceMessage>.self))
                                expect(nextPage.items).to(haveCount(50))

                                let members = nextPage.items 
                                expect(members).to(allPass({ member in
                                    return NSRegularExpression.match(member!.clientId, pattern: expectedPattern)
                                        && (member!.data as! [String]) == expectedData
                                }))

                                expect(nextPage.hasNext).to(beFalse())
                                expect(nextPage.isLast).to(beTrue())
                                done()
                            }
                        }
                    }
                }

            }

            // RTP13
            it("Presence#syncComplete returns true if the initial SYNC operation has completed") {
                let options = AblyTests.commonAppSetup()

                var disposable = [ARTRealtime]()
                defer {
                    for clientItem in disposable {
                        clientItem.dispose()
                        clientItem.close()
                    }
                }

                disposable += [AblyTests.addMembersSequentiallyToChannel("test", members: 250, options: options)]

                let client = AblyTests.newRealtime(options)
                defer { client.dispose(); client.close() }
                let channel = client.channels.get("test")
                channel.attach()

                expect(channel.presence.syncComplete).to(beFalse())
                expect(channel.state).toEventually(equal(ARTRealtimeChannelState.attached), timeout: testTimeout)

                let transport = client.internal.transport as! TestProxyTransport
                transport.beforeProcessingReceivedMessage = { protocolMessage in
                    if protocolMessage.action == .sync {
                        expect(channel.presence.internal.syncComplete_nosync()).to(beFalse())
                    }
                }

                expect(channel.presence.syncComplete).toEventually(beTrue(), timeout: testTimeout)
                expect(transport.protocolMessagesReceived.filter({ $0.action == .sync })).to(haveCount(3))
            }

            // RTP14
            context("enterClient") {

                // RTP14a, RTP14b, RTP14c, RTP14d
                it("enters into presence on a channel on behalf of another clientId") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channel = client.channels.get("test")
                    expect(channel.internal.presenceMap.members).to(haveCount(0))

                    let expectedData = ["test":1]

                    var encodeNumberOfCalls = 0
                    let hookEncode = channel.internal.dataEncoder.testSuite_injectIntoMethod(after: #selector(ARTDataEncoder.encode(_:))) {
                        encodeNumberOfCalls += 1
                    }
                    defer { hookEncode.remove() }

                    var decodeNumberOfCalls = 0
                    let hookDecode = channel.internal.dataEncoder.testSuite_injectIntoMethod(after: #selector(ARTDataEncoder.decode(_:encoding:))) {
                        decodeNumberOfCalls += 1
                    }
                    defer { hookDecode.remove() }


                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.enterClient("test", data: expectedData)  { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    channel.presence.enterClient("john", data: nil)
                    channel.presence.enterClient("sara", data: nil)
                    expect(channel.internal.presenceMap.members).toEventually(haveCount(3), timeout: testTimeout)

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get() { members, error in
                            guard let members = members?.reduce([String:ARTPresenceMessage](), { (dictionary, item) in
                                return dictionary + [item.clientId ?? "":item]
                            }) else { fail("No members"); done(); return }

                            expect(members["test"]!.data as? NSDictionary).to(equal(expectedData as NSDictionary?))
                            expect(members["john"]).toNot(beNil())
                            expect(members["sara"]).toNot(beNil())
                            done()
                        }
                    }

                    expect(encodeNumberOfCalls).to(equal(1))
                    expect(decodeNumberOfCalls).to(equal(1))
                }

                // RTP14d
                it("should be present all the registered members on a presence channel") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.dispose(); client.close() }
                    let channelName = NSUUID().uuidString
                    let channel = client.channels.get(channelName)

                    let john = "john"
                    let max = "max"

                    waitUntil(timeout: testTimeout) { done in
                        let partialDone = AblyTests.splitDone(4, done: done)
                        channel.presence.subscribe { message in
                            expect(message.clientId).to(satisfyAnyOf(equal(john), equal(max)))
                            partialDone()
                        }
                        channel.presence.enterClient(john, data: nil) { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                        channel.presence.enterClient(max, data: nil) { error in
                            expect(error).to(beNil())
                            partialDone()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get { members, error in
                            expect(error).to(beNil())
                            guard let members = members else {
                                fail("Members is nil"); done(); return
                            }
                            expect(members).to(haveCount(2))
                            let clientIds = members.map({ $0.clientId })
                            // Cannot guarantee the order
                            expect(clientIds).to(equal([john, max]) || equal([max, john]))
                            done()
                        }
                    }
                }
            }
            
            context("presence message attributes") {
                
                // TP3a
                it("if the presence message does not contain an id, it should be set to protocolMsgId:index") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    let client = ARTRealtime(options: options)
                    defer { client.dispose(); client.close() }

                    let protocolMessage = ARTProtocolMessage()
                    protocolMessage.id = "protocolId"
                    let presenceMessage = ARTPresenceMessage()
                    presenceMessage.clientId = "clientId"
                    presenceMessage.action = .enter
                    protocolMessage.presence = [presenceMessage]
                    
                    waitUntil(timeout: testTimeout) { done in
                        client.connection.once(.connected) { _ in
                            let channel = client.channels.get(NSUUID().uuidString)
                            channel.presence.subscribe(.enter) { message in
                                expect(message.id).to(equal("protocolId:0"))
                                done()
                            }
                            AblyTests.queue.async {
                                channel.internal.onPresence(protocolMessage)
                            }
                        }
                        client.connect()
                    }
                }
            }

        }
    }
}
