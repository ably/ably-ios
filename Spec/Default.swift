//
//  Default.swift
//  Ably
//
//  Created by Marat Al on 27.05.2021.
//  Copyright © 2021 Ably. All rights reserved.
//

import Ably
import Nimble
import Quick
import Foundation

class Default: QuickSpec {

    override func spec() {

        describe("Default") {

            context("String canonization") {

                it("should remove spaces") {
                    
                    let result = canonizeStringAsAgentToken(" iPhone12 -5 ")
                    
                    expect(result).to(equal("iPhone12-5"))
                }

                it("should return an empty string when an empty string passed") {
                    
                    let result = canonizeStringAsAgentToken("")
                    
                    expect(result).to(equal(""))
                }

                it("should return the input string itself if it contains only allowed characters") {
                    
                    let result = canonizeStringAsAgentToken("iPhone12-5")
                    
                    expect(result).to(equal("iPhone12-5"))
                }

                it("should return an empty string if the input string contains only disallowed characters") {
                    
                    let result = canonizeStringAsAgentToken(":) )))")
                    
                    expect(result).to(equal(""))
                }

                it("should return an empty string if the input string contains only one disallowed character") {
                    
                    let result = canonizeStringAsAgentToken(")")
                    
                    expect(result).to(equal(""))
                }

                it("should return the input string itself if it contains only one allowed character") {
                    
                    let result = canonizeStringAsAgentToken("+")
                    
                    expect(result).to(equal("+"))
                }
            }
        }
    }
}
