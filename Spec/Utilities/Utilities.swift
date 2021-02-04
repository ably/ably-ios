//
//  Utilities.swift
//  ably
//
//  Created by Toni Cárdenas on 30/1/16.
//  Copyright © 2016 Ably. All rights reserved.
//

import Ably
import Nimble
import Quick
import Foundation

class Utilities: QuickSpec {
    override func spec() {
        describe("Utilities") {

            context("JSON Encoder") {
                var jsonEncoder: ARTJsonLikeEncoder!
                beforeEach {
                    jsonEncoder = ARTJsonLikeEncoder()
                    jsonEncoder.delegate = ARTJsonEncoder()
                }

                it("should decode a protocol message that has an error without a message") {
                    let jsonObject: NSDictionary = [
                        "action": 9,
                        "error": [
                            "code": 40142,
                            "statusCode": "401",
                        ]
                    ]
                    let data = try! JSONSerialization.data(withJSONObject: jsonObject, options: [])
                    guard let protocolMessage = try? jsonEncoder.decodeProtocolMessage(data) else {
                        fail("Decoder has failed"); return
                    }
                    guard let error = protocolMessage.error else {
                        fail("Error is empty"); return
                    }
                    expect(error.message).to(equal(""))
                }

                it("should encode a protocol message that has invalid data") {
                    let pm = ARTProtocolMessage()
                    pm.action = .message
                    pm.channel = "foo"
                    pm.messages = [ARTMessage(name: "status", data: NSDate(), clientId: "user")]
                    var result: Data?
                    expect{ result = try jsonEncoder.encode(pm) }.to(throwError { error in
                        let e = error as NSError
                        expect(e.domain).to(equal(ARTAblyErrorDomain))
                        expect(e.code).to(equal(Int(ARTClientCodeError.invalidType.rawValue)))
                        expect(e.localizedDescription).to(contain("Invalid type in JSON write"))
                        })
                    expect(result).to(beNil())
                }

                it("should decode data with malformed JSON") {
                    let malformedJSON = "{...}"
                    let data = malformedJSON.data(using: String.Encoding.utf8)!
                    var result: AnyObject?
                    expect{ result = try ARTJsonEncoder().decode(data) as AnyObject? }.to(throwError { error in
                        let e = error as NSError
                        expect(e.localizedDescription).to(contain("data couldn’t be read"))
                    })
                    expect(result).to(beNil())
                }

                it("should decode data with malformed MsgPack") {
                    let data = NSData()
                    var result: AnyObject?
                    expect{ result = try ARTMsgPackEncoder().decode(data as Data) as! (Data) as (Data) as AnyObject? }.to(throwError { error in
                        expect(error).toNot(beNil())
                    })
                    expect(result).to(beNil())
                }

                context("in Realtime") {
                    it("should handle and emit the invalid data error") {
                        let options = AblyTests.commonAppSetup()
                        let realtime = ARTRealtime(options: options)
                        defer { realtime.close() }
                        let channel = realtime.channels.get("foo")
                        waitUntil(timeout: testTimeout) { done in
                            channel.publish("test", data: NSDate()) { error in
                                guard let error = error else {
                                    fail("Error shouldn't be nil"); done(); return
                                }
                                expect(error.message).to(contain("encoding failed"))
                                expect(error.reason).to(contain("must be NSString, NSData, NSArray or NSDictionary"))
                                done()
                            }
                        }
                        waitUntil(timeout: testTimeout) { done in
                            channel.publish([ARTMessage(name: nil, data: NSDate()), ARTMessage(name: nil, data: NSDate())]) { error in
                                guard let error = error else {
                                    fail("Error shouldn't be nil"); done(); return
                                }
                                expect(error.message).to(contain("encoding failed"))
                                expect(error.reason).to(contain("must be NSString, NSData, NSArray or NSDictionary"))
                                done()
                            }
                        }
                    }

                    it("should ignore invalid transport message") {
                        let options = AblyTests.commonAppSetup()
                        let realtime = ARTRealtime(options: options)
                        defer { realtime.close() }
                        let channel = realtime.channels.get("foo")

                        // Garbage values (whatever is on the heap)
                        let bytes = UnsafeMutablePointer<Int>.allocate(capacity: 1)
                        defer { bytes.deallocate() }
                        let data = NSData(bytes: bytes, length: MemoryLayout<Int>.size)

                        waitUntil(timeout: testTimeout) { done in
                            channel.attach { error in
                                expect(error).to(beNil())
                                realtime.connection.once { _ in
                                    fail("Should not receive any connection change state")
                                }
                                channel.once { _ in
                                    fail("Should not receive any channel change state")
                                }
                                channel.subscribe { _ in
                                    fail("Should not receive any message")
                                }
                                var result: AnyObject?
                                expect{ result = realtime.internal.transport?.receive(with: data as Data) }.toNot(raiseException())
                                expect(result).to(beNil())
                                done()
                            }
                        }

                        realtime.connection.off()
                        channel.off()
                        channel.unsubscribe()
                    }
                }

                context("in Rest") {
                    it("should handle and emit the invalid data error") {
                        let options = AblyTests.commonAppSetup()
                        let rest = ARTRest(options: options)
                        let channel = rest.channels.get("foo")
                        waitUntil(timeout: testTimeout) { done in
                            channel.publish("test", data: NSDate()) { error in
                                guard let error = error else {
                                    fail("Error shouldn't be nil"); done(); return
                                }
                                expect(error.message).to(contain("encoding failed"))
                                expect(error.reason).to(contain("must be NSString, NSData, NSArray or NSDictionary"))
                                done()
                            }
                        }
                        waitUntil(timeout: testTimeout) { done in
                            channel.publish([ARTMessage(name: nil, data: NSDate()), ARTMessage(name: nil, data: NSDate())]) { error in
                                guard let error = error else {
                                    fail("Error shouldn't be nil"); done(); return
                                }
                                expect(error.message).to(contain("encoding failed"))
                                expect(error.reason).to(contain("must be NSString, NSData, NSArray or NSDictionary"))
                                done()
                            }
                        }
                    }

                    it("should ignore invalid response payload") {
                        let options = AblyTests.commonAppSetup()
                        let rest = ARTRest(options: options)
                        let testHTTPExecutor = TestProxyHTTPExecutor(options.logHandler)
                        rest.internal.httpExecutor = testHTTPExecutor
                        let channel = rest.channels.get("foo")

                        // Garbage values (whatever is on the heap)
                        let bytes = UnsafeMutablePointer<Int>.allocate(capacity: 1)
                        defer { bytes.deallocate() }
                        let data = NSData(bytes: bytes, length: MemoryLayout<Int>.size)

                        testHTTPExecutor.simulateIncomingPayloadOnNextRequest(data as Data)
                        waitUntil(timeout: testTimeout) { done in
                            channel.publish(nil, data: nil) { error in
                                expect(error).to(beNil()) //ignored
                                done()
                            }
                        }

                        testHTTPExecutor.simulateIncomingPayloadOnNextRequest(data as Data)
                        waitUntil(timeout: testTimeout) { done in
                            channel.history { result, error in
                                guard let error = error else {
                                    fail("Error is nil"); done(); return
                                }
                                expect(error.reason).to(contain("JSON text did not start with array or object and option to allow fragments not set"))
                                done()
                            }
                        }
                    }
                }
            }

            context("EventEmitter") {

                var eventEmitter = ARTInternalEventEmitter<NSString, AnyObject>(queue: AblyTests.queue)
                var receivedFoo1: Int?
                var receivedFoo2: Int?
                var receivedBar: Int?
                var receivedBarOnce: Int?
                var receivedAll: Int?
                var receivedAllOnce: Int?
                weak var listenerFoo1: ARTEventListener?
                weak var listenerAll: ARTEventListener?

                beforeEach {
                    eventEmitter = ARTInternalEventEmitter(queue: AblyTests.queue)
                    receivedFoo1 = nil
                    receivedFoo2 = nil
                    receivedBar = nil
                    receivedBarOnce = nil
                    receivedAll = nil
                    listenerFoo1 = eventEmitter.on("foo", callback: { receivedFoo1 = $0 as? Int })
                    eventEmitter.on("foo", callback: { receivedFoo2 = $0 as? Int })
                    eventEmitter.on("bar", callback: { receivedBar = $0 as? Int })
                    eventEmitter.once("bar", callback: { receivedBarOnce = $0 as? Int })
                    listenerAll = eventEmitter.on { receivedAll = $0 as? Int }
                    eventEmitter.once { receivedAllOnce = $0 as? Int }
                }

                it("should emit events to all relevant listeners") {
                    eventEmitter.emit("foo", with: 123 as AnyObject?)

                    expect(receivedFoo1).to(equal(123))
                    expect(receivedFoo2).to(equal(123))
                    expect(receivedBar).to(beNil())
                    expect(receivedAll).to(equal(123))
                    
                    eventEmitter.emit("bar", with:456 as AnyObject?)
                    
                    expect(receivedFoo1).to(equal(123))
                    expect(receivedFoo2).to(equal(123))
                    expect(receivedBar).to(equal(456))
                    expect(receivedAll).to(equal(456))
                    
                    eventEmitter.emit("qux", with:789 as AnyObject?)
                    
                    expect(receivedAll).toEventually(equal(789), timeout: testTimeout)
                }
                
                it("should only call once listeners once for its event") {
                    eventEmitter.emit("foo", with: 123 as AnyObject?)

                    expect(receivedBarOnce).to(beNil())
                    expect(receivedAllOnce).to(equal(123))
                    
                    eventEmitter.emit("bar", with: 456 as AnyObject?)
                    
                    expect(receivedBarOnce).to(equal(456))
                    expect(receivedAllOnce).to(equal(123))

                    eventEmitter.emit("bar", with: 789 as AnyObject?)
                    
                    expect(receivedBarOnce).to(equal(456))
                    expect(receivedAllOnce).to(equal(123))
                }
                
                context("calling off with a single listener argument") {
                    it("should stop receiving events when calling off with a single listener argument") {
                        eventEmitter.off(listenerFoo1!)
                        eventEmitter.emit("foo", with: 123 as AnyObject?)
                        
                        expect(receivedFoo1).to(beNil())
                        expect(receivedFoo2).to(equal(123))
                        expect(receivedAll).to(equal(123))
                        
                        eventEmitter.emit("bar", with: 222 as AnyObject?)
                        
                        expect(receivedFoo2).to(equal(123))
                        expect(receivedAll).to(equal(222))
                        
                        eventEmitter.off(listenerAll!)
                        eventEmitter.emit("bar", with: 333 as AnyObject?)
                        
                        expect(receivedAll).to(equal(222))
                    }

                    it("should remove the timeout") {
                        listenerFoo1!.setTimer(0.1, onTimeout: {
                            fail("onTimeout callback shouldn't have been called")
                        }).startTimer()
                        eventEmitter.off(listenerFoo1!)
                        waitUntil(timeout: DispatchTimeInterval.milliseconds(300)) { done in
                            AblyTests.queue.asyncAfter(deadline: DispatchTime.now() + 0.3) {
                                done()
                            }
                        }
                    }
                }
                
                context("calling off with listener and event arguments") {
                    it("should still receive events if off doesn't match the listener's criteria") {
                        eventEmitter.off("foo", listener: listenerAll!)
                        eventEmitter.emit("foo", with: 111 as AnyObject?)

                        expect(receivedFoo1).to(equal(111))
                        expect(receivedAll).to(equal(111))
                    }

                    it("should stop receive events if off matches the listener's criteria") {
                        eventEmitter.off("foo", listener: listenerFoo1!)
                        eventEmitter.emit("foo", with: 111 as AnyObject?)

                        expect(receivedFoo1).to(beNil())
                        expect(receivedAll).to(equal(111))
                    }
                }
                
                context("calling off with no arguments") {
                    it("should remove all listeners") {
                        eventEmitter.off()
                        eventEmitter.emit("foo", with: 111 as AnyObject?)
                        
                        expect(receivedFoo1).to(beNil())
                        expect(receivedFoo2).to(beNil())
                        expect(receivedAll).to(beNil())
                        
                        eventEmitter.emit("bar", with: 111 as AnyObject?)
                        
                        expect(receivedBar).to(beNil())
                        expect(receivedBarOnce).to(beNil())
                        expect(receivedAll).to(beNil())
                    }
                    
                    it("should allow listening again") {
                        eventEmitter.off()
                        eventEmitter.on("foo", callback: { receivedFoo1 = $0 as? Int })
                        eventEmitter.emit("foo", with: 111 as AnyObject?)
                        expect(receivedFoo1).to(equal(111))
                    }

                    it("should remove all timeouts") {
                        listenerFoo1!.setTimer(0.1, onTimeout: {
                            fail("onTimeout callback shouldn't have been called")
                        }).startTimer()
                        listenerAll!.setTimer(0.1, onTimeout: {
                            fail("onTimeout callback shouldn't have been called")
                        }).startTimer()
                        eventEmitter.off()
                        waitUntil(timeout: DispatchTimeInterval.milliseconds(300)) { done in
                            AblyTests.queue.asyncAfter(deadline: .now() + 0.15) {
                                done()
                            }
                        }
                    }
                }

                context("the timed method") {
                    it("should not call onTimeout if the deadline isn't reached") {
                        weak var timer = listenerFoo1!.setTimer(0.2, onTimeout: {
                            fail("onTimeout callback shouldn't have been called")
                        })
                        waitUntil(timeout: DispatchTimeInterval.seconds(1)) { done in
                            timer?.startTimer()
                            eventEmitter.emit("foo", with: 123 as AnyObject?)
                            AblyTests.queue.asyncAfter(deadline: .now() + 0.3) {
                                expect(receivedFoo1).toNot(beNil())
                                done()
                            }
                        }
                    }

                    it("should call onTimeout and off the listener if the deadline is reached") {
                        var calledOnTimeout = false
                        let beforeEmitting = NSDate()
                        listenerFoo1!.setTimer(0.3, onTimeout: {
                            calledOnTimeout = true
                            expect(NSDate()).to(beCloseTo(beforeEmitting.addingTimeInterval(0.3), within: 0.2))
                        }).startTimer()
                        waitUntil(timeout: DispatchTimeInterval.milliseconds(500)) { done in
                            AblyTests.queue.asyncAfter(deadline: .now() + 0.35) {
                                expect(calledOnTimeout).to(beTrue())
                                eventEmitter.emit("foo", with: 123 as AnyObject?)
                                expect(receivedFoo1).to(beNil())
                                done()
                            }
                        }
                    }
                }
                
                context("set of listeners") {
                    
                    // RTE6a
                    it("should not change over the course of the emit") {
                        var firstCallbackCalled = false;
                        var secondCallbackCalled = false;
                        eventEmitter.on("a", callback: { _ in
                            firstCallbackCalled = true
                            eventEmitter.on("b", callback: { _ in
                                secondCallbackCalled = true
                            })
                        })
                        eventEmitter.emit("a", with: "123" as AnyObject?)
                        expect(firstCallbackCalled).to(beTrue())
                        expect(secondCallbackCalled).to(beFalse())
                    }
                }
            }

            context("Logger") {

                it("should have a history of logs") {
                    let options = AblyTests.commonAppSetup()
                    let realtime = ARTRealtime(options: options)
                    realtime.internal.logger.logLevel = .verbose
                    defer { realtime.close() }
                    let channel = realtime.channels.get("foo")

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach { error in
                            expect(error).to(beNil())
                            done()
                        }
                    }

                    expect(realtime.internal.logger.history.count).toNot(beGreaterThan(100))
                    expect(realtime.internal.logger.history.map{ $0.message }.first).to(contain("channel state transitions from 1 - Attaching to 2 - Attached"))
                    expect(realtime.internal.logger.history.filter{ $0.message.contains("realtime state transitions to 2 - Connected") }).to(haveCount(1))
                }

            }
            
            context("maxMessageSize") {
                let data = ["test": "test"]
                let extras = ["push": ["key": "value"]]
                let clientId = "clientId"

                it("calculates maxMessageSize of a Message with name and data") {
                    let message = ARTMessage(name: "this is name", data: data)
                    let expectedSize = "{\"test\":\"test\"}".count + message.name!.count
                    expect(message.messageSize()).to(equal(expectedSize))
                }

                it("calculates maxMessageSize of a Message with name, data and extras") {
                    let message = ARTMessage(name: "this is name", data: data)
                    message.extras = extras as ARTJsonCompatible
                    let expectedSize = "{\"test\":\"test\"}".count + "{\"push\":{\"key\":\"value\"}}".count + message.name!.count
                    expect(message.messageSize()).to(equal(expectedSize))
                }

                it("calculates maxMessageSize of a Message with name, data, clientId and extras") {
                    let message = ARTMessage(name: "this is name", data: data)
                    message.clientId = clientId
                    message.extras = extras as ARTJsonCompatible
                    let expectedSize = "{\"test\":\"test\"}".count + "{\"push\":{\"key\":\"value\"}}".count + clientId.count + message.name!.count
                    expect(message.messageSize()).to(equal(expectedSize))
                }
            }
        }
    }
}
