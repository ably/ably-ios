//
//  Stringifiable.swift
//  Ably
//
//  Created by Łukasz Szyszkowski on 21/06/2021.
//  Copyright © 2021 Ably. All rights reserved.
//

import Ably
import Quick
import Nimble

class Stringifiable: QuickSpec {
    override func spec() {
        describe("Stringifiable") {
            context("type conversion") {
                it("as string") {
                    expect(
                        ARTStringifiable(string: "Lorem Ipsum").stringValue
                    )
                    .to(
                        equal("Lorem Ipsum")
                    )
                }
                
                it("as bool [true]") {
                    expect {
                        ARTStringifiable(bool: true).stringValue
                    }
                    .to(
                        equal("true")
                    )
                }
                
                it("as bool [false]") {
                    expect {
                        ARTStringifiable(bool: false).stringValue
                    }
                    .to(
                        equal("false")
                    )
                }
                
                it("as integer that is not treated as bool [false]") {
                    expect {
                        ARTStringifiable(number: NSNumber(value: 0)).stringValue
                    }
                    .to(
                        equal("0")
                    )
                }
                
                it("as integer that is not treated as bool [true]") {
                    expect {
                        ARTStringifiable(number: NSNumber(value: 1)).stringValue
                    }
                    .to(
                        equal("1")
                    )
                }
                
                it("as number [Int]") {
                    expect {
                        ARTStringifiable(number: NSNumber(value: 12)).stringValue
                    }
                    .to(
                        equal("12")
                    )
                }
                
                it("as number [Float 1 decimal digit]") {
                    expect {
                        ARTStringifiable(number: NSNumber(value: 0.1)).stringValue
                    }
                    .to(
                        equal("0.1")
                    )
                }
                
                it("as number [Float 2 decimal digits]") {
                    expect {
                        ARTStringifiable(number: NSNumber(value: 0.12)).stringValue
                    }
                    .to(
                        equal("0.12")
                    )
                }
                
                it("as number [Float 4 decimal digits]") {
                    expect {
                        ARTStringifiable(number: NSNumber(value: 0.1234)).stringValue
                    }
                    .to(
                        equal("0.1234")
                    )
                }
            }
        }
    }
}
