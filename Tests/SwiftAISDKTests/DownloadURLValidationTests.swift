import Foundation
import Testing
@testable import SwiftAISDK

@Test func downloadURLValidationAllowsPublicHTTPAndDataURLs() throws {
    let allowed = [
        "https://example.com/image.png",
        "http://example.com/image.png",
        "https://203.0.113.1/file",
        "https://example.com:8080/file",
        "data:text/plain;base64,aGVsbG8=",
        "http://172.15.0.1/file",
        "http://172.32.0.1/file",
        "http://[::ffff:203.0.113.1]/file"
    ]

    for url in allowed {
        #expect(try validateDownloadURL(url).absoluteString == url)
    }
}

@Test func downloadURLValidationBlocksUnsafeSchemesAndMalformedURLs() {
    let blocked = [
        "file:///etc/passwd",
        "ftp://example.com/file",
        "javascript:alert(1)",
        "not-a-url"
    ]

    for url in blocked {
        #expect(throws: Error.self) {
            _ = try validateDownloadURL(url)
        }
    }
}

@Test func downloadURLValidationBlocksLocalHostnames() {
    let blocked = [
        "http://localhost/file",
        "http://localhost:3000/file",
        "http://myhost.local/file",
        "http://app.localhost/file"
    ]

    for url in blocked {
        #expect(throws: Error.self) {
            _ = try validateDownloadURL(url)
        }
    }
}

@Test func downloadURLValidationBlocksPrivateIPv4Ranges() {
    let blocked = [
        "http://127.0.0.1/file",
        "http://127.255.0.1/file",
        "http://10.0.0.1/file",
        "http://172.16.0.1/file",
        "http://172.31.255.255/file",
        "http://192.168.1.1/file",
        "http://169.254.169.254/latest/meta-data/",
        "http://0.0.0.0/file"
    ]

    for url in blocked {
        #expect(throws: Error.self) {
            _ = try validateDownloadURL(url)
        }
    }
}

@Test func downloadURLValidationBlocksPrivateIPv6Ranges() {
    let blocked = [
        "http://[::1]/file",
        "http://[0:0:0:0:0:0:0:1]/file",
        "http://[::]/file",
        "http://[fc00::1]/file",
        "http://[fd12::1]/file",
        "http://[fe80::1]/file",
        "http://[::ffff:127.0.0.1]/file",
        "http://[::ffff:10.0.0.1]/file",
        "http://[::ffff:169.254.169.254]/file",
        "http://[::ffff:7f00:1]/file"
    ]

    for url in blocked {
        #expect(throws: Error.self) {
            _ = try validateDownloadURL(url)
        }
    }
}
