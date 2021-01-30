//
//  GCDTest.swift
//  Ably
//
//  Created by Mikey on 12/01/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

import XCTest

class GCDTest: XCTestCase {
    func testScheduledBlockHandleDerefsBlockAfterInvoke() {
        let invokedExpectation = self.expectation(description: "scheduled block invoked")
        let obj = NSObject()

        var scheduledBlock = artDispatchScheduled(0, .main) {
            _ = obj
            invokedExpectation.fulfill()
        }

        waitForExpectations(timeout: 2, handler: nil)

        _ = scheduledBlock // silence warning
        scheduledBlock = nil

        XCTAssertEqual(CFGetRetainCount(obj), 1)
    }
}
