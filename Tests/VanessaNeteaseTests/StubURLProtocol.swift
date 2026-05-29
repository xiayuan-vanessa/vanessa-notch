import Foundation

/// 测试用 URLProtocol:按「请求 URL 包含某子串」返回预置响应,断网时抛错。
final class StubURLProtocol: URLProtocol {
    struct Stub { let data: Data; let statusCode: Int; let error: Error? }
    /// 子串 -> 响应。匹配第一个被 url.absoluteString 包含的 key。
    nonisolated(unsafe) static var stubs: [String: Stub] = [:]

    static func reset() { stubs = [:] }
    static func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        guard let (_, stub) = StubURLProtocol.stubs.first(where: { url.contains($0.key) }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error); return
        }
        let resp = HTTPURLResponse(url: request.url!, statusCode: stub.statusCode,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
