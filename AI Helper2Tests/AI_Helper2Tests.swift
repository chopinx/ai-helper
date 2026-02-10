//
//  AI_Helper2Tests.swift
//  AI Helper2Tests
//
//  Created by Qinbang Xiao on 28/7/25.
//

import Testing
@testable import AI_Helper2

struct AI_Helper2Tests {

    @Test func appModuleImports() {
        // Verify the test target can import the main module
        let provider = AIProvider.openai
        #expect(provider.rawValue == "OpenAI")
    }
}
