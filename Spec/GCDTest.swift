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
        
        // retain counter: 1
        var object = NSObject()
        
        // store reference for above weakified
        weak var weakObject = object
        
        // prepare schedule block
        var scheduledBlock = artDispatchScheduled(0, .main) { [object] in
            // retain counter +1 -> sum: 2
            _ = object
            invokedExpectation.fulfill()
        }

        // invoke block
        _ = scheduledBlock
        
        waitForExpectations(timeout: 2, handler: nil)
        
        // destroy block reference
        // `object` retain counter -1, sum: 1
        scheduledBlock = nil

        // assign new object to old variable
        // at this point old `object` should be destroyed, retain counter: -1, sum: 0 -> Destroy
        object = NSObject()
        
        // check if old `object` reference was destroyed
        XCTAssertNil(weakObject)
    }
}
