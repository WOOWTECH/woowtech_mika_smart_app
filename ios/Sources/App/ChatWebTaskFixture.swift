#if DEBUG
import AssistantModels
import Foundation
import Network

/// A synthetic website on 127.0.0.1 for chat web task tests: a job search with
/// query strings, job pages, a shop list that grows on scrolling, AI news, a
/// sign-in page and a redirect to a log-out path. Debug only; the existing
/// Debug ATS exception for 127.0.0.1 covers it. Never real sites or accounts.
final class ChatWebTaskFixture: @unchecked Sendable {
    static let flag = "-UITestChatWeb"
    static let shared: ChatWebTaskFixture? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITestMode"), arguments.contains(flag),
              !arguments.contains(where: { $0.hasPrefix("-Live") }) else { return nil }
        return ChatWebTaskFixture()
    }()

    private let queue = DispatchQueue(label: "io.woowtech.chat-web-fixture")
    private var listener: NWListener?
    private var waiters: [CheckedContinuation<URL, Error>] = []
    private var origin: URL?
    private(set) var requests: [String] = []
    struct Unavailable: Error {}

    /// The origin once started; the model fixture reads it to build URLs.
    var originURL: URL? { queue.sync { origin } }
    var requestedPaths: [String] { queue.sync { requests } }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                if let origin { continuation.resume(returning: origin); return }
                waiters.append(continuation)
                guard listener == nil else { return }
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                    let server = try NWListener(using: parameters)
                    listener = server
                    server.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
                    server.stateUpdateHandler = { [weak self, weak server] state in
                        guard let self, let server else { return }
                        switch state {
                        case .ready:
                            guard let port = server.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)") else {
                                self.fail(); return
                            }
                            self.origin = url
                            let pending = self.waiters; self.waiters = []
                            pending.forEach { $0.resume(returning: url) }
                        case .failed, .cancelled: self.fail()
                        default: break
                        }
                    }
                    server.start(queue: queue)
                } catch { fail() }
            }
        }
    }

    func stop() { queue.async { [self] in listener?.cancel(); listener = nil; origin = nil } }

    private func fail() {
        let pending = waiters; waiters = []
        pending.forEach { $0.resume(throwing: Unavailable()) }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, done, error in
            guard let self else { connection.cancel(); return }
            var received = buffer
            if let data { received.append(data) }
            guard error == nil, received.count <= 64 * 1024 else { connection.cancel(); return }
            guard let end = received.range(of: Data("\r\n\r\n".utf8)) else {
                if done { connection.cancel() } else { self.receive(connection, buffer: received) }
                return
            }
            let head = String(decoding: received[..<end.lowerBound], as: UTF8.self)
            // A form's body follows the head; answer once it has all arrived.
            let length = head.split(separator: "\r\n").compactMap { line -> Int? in
                let pair = line.split(separator: ":", maxSplits: 1)
                guard pair.count == 2, pair[0].lowercased() == "content-length" else { return nil }
                return Int(pair[1].trimmingCharacters(in: .whitespaces))
            }.first ?? 0
            if received.count - end.upperBound < min(length, 16 * 1024) && !done {
                self.receive(connection, buffer: received); return
            }
            let parts = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
            let target = parts.count >= 2 ? String(parts[1]) : "/"
            self.requests.append((parts.first.map(String.init) ?? "?") + " " + target)
            let reply = Self.response(method: parts.first.map(String.init) ?? "", target: target)
            connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private static func escape(_ text: String) -> String {
        text.unicodeScalars.map { ["<": "&lt;", ">": "&gt;", "&": "&amp;", "'": "&#39;", "\"": "&quot;", "\\": ""][String($0)] ?? String($0) }.joined()
    }

    static func response(method: String, target: String) -> Data {
        let components = URLComponents(string: target)
        let path = components?.path ?? "/"
        let query = Dictionary((components?.queryItems ?? []).map { ($0.name, escape($0.value ?? "")) }, uniquingKeysWith: { a, _ in a })
        func reply(_ status: String, _ headers: [String], _ body: String) -> Data {
            let bytes = Data(body.utf8)
            let lines = ["HTTP/1.1 " + status] + headers + ["Content-Length: \(bytes.count)", "Connection: close", "Cache-Control: no-store", "", ""]
            return Data(lines.joined(separator: "\r\n").utf8) + bytes
        }
        func page(_ title: String, _ body: String) -> Data {
            reply("200 OK", ["Content-Type: text/html; charset=utf-8"], """
            <!doctype html><html lang="zh-Hant"><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1"><title>\(title)</title></head>
            <body><nav><a href="/">網站首頁</a> <a href="/help">說明</a> <a href="/account/login">登入</a></nav>
            <main>\(body)</main><footer><a href="/about">關於我們</a></footer></body></html>
            """)
        }
        if method == "POST" && path == "/shop/ordered" {
            return page("訂單成立", "<h1>訂單成立</h1><p>訂單已成立，請付款 NT$ 1,290。</p><a href=\"/shop/pay\">確認付款</a>")
        }
        guard method == "GET" else { return reply("405 Method Not Allowed", ["Allow: GET"], "") }
        switch path {
        case "/jobs/search":
            let keyword = query["keyword"] ?? ""
            let items = (1...6).map { n in
                "<li><a href=\"/jobs/job/\(n)\">\(keyword) 工程師（測試公司 \(n)）</a>：月薪 \(45 + n * 5),000～\(60 + n * 5),000 元</li>"
            }.joined()
            return page("「\(keyword)」工作 - 測試人力銀行", "<h1>搜尋「\(keyword)」共 6 筆職缺</h1><ol>\(items)</ol>")
        case let job where job.hasPrefix("/jobs/job/"):
            let n = Int(job.dropFirst("/jobs/job/".count)) ?? 0
            guard (1...6).contains(n) else { break }
            return page("工程師（測試公司 \(n)）", """
            <h1>工程師（測試公司 \(n)）</h1><p>工作地點：台北市</p>
            <p>薪資：月薪 \(45 + n * 5),000～\(60 + n * 5),000 元</p>
            <p>條件：\(n + 1) 年以上 Swift 經驗，熟悉 SwiftUI。</p>
            """)
        case "/shop/search":
            let keyword = query["keyword"] ?? ""
            let first = (1...4).map { "<li>\(keyword) 型號 \($0)：NT$ \(990 + $0 * 100)</li>" }.joined()
            return page("\(keyword) - 測試購物", """
            <h1>「\(keyword)」商品</h1><ul id="list">\(first)</ul><div style="height:3000px"></div>
            <script>
            let more = false;
            addEventListener('scroll', () => {
              if (more || scrollY < 200) return; more = true;
              const list = document.getElementById('list');
              for (let i = 5; i <= 8; i++) { const li = document.createElement('li'); li.textContent = '\(keyword) 型號 ' + i + '：NT$ ' + (990 + i * 100); list.appendChild(li); }
            });
            </script>
            """)
        case "/shop/cart":
            return page("購物車 - 測試購物", """
            <h1>購物車</h1><p>無線耳機 1 副</p><p>合計：NT$ 1,290</p>
            <form method="post" action="/shop/ordered"><button>送出訂單</button></form>
            """)
        case "/news":
            let items = (1...3).map { "<li><a href=\"/news/\($0)\">AI 新聞 \($0)：測試標題</a></li>" }.joined()
            return page("AI 新聞 - 測試新聞", "<h1>最近的 AI 新聞</h1><ul>\(items)</ul>")
        case let article where article.hasPrefix("/news/"):
            let n = Int(article.dropFirst("/news/".count)) ?? 0
            guard (1...3).contains(n) else { break }
            return page("AI 新聞 \(n)：測試標題", "<h1>AI 新聞 \(n)</h1><p>重點一：測試內容 \(n)A。</p><p>重點二：測試內容 \(n)B。</p><p>重點三：測試內容 \(n)C。</p>")
        case "/account/login":
            return page("登入", "<form method=\"post\" action=\"/account/login\"><input name=\"user\"><input type=\"password\" name=\"pw\"><button>登入</button></form>")
        case "/go-logout":
            return reply("302 Found", ["Location: /account/logout"], "")
        case "/account/logout":
            return page("已登出", "<p>你已登出。</p>")
        case "/":
            return page("測試首頁", "<p>測試網站首頁。</p><a href=\"/jobs/search?keyword=iOS\">找工作</a> <a href=\"/news\">新聞</a>")
        default: break
        }
        return reply("404 Not Found", ["Content-Type: text/html; charset=utf-8"], "<p>找不到頁面</p>")
    }
}

/// What the Debug model fixture answers in web tasks: a fixed script per
/// example, read from the actual observations, so the native App path (entry,
/// task tab, runner, card, transcript) runs without a model provider.
enum ChatWebTaskUITestModel {
    enum Script: String { case jobs, shop, news, stop, order }

    static func script(for prompt: String) -> Script? {
        if prompt == "[fixture:web-stop]" { return .stop }
        if prompt == "[fixture:web-order]" { return .order }
        if prompt.contains("104") { return .jobs }
        if prompt.lowercased().contains("momo") { return .shop }
        if prompt.contains("AI") && (prompt.contains("新聞") || prompt.lowercased().contains("news")) { return .news }
        return nil
    }

    /// The command that starts the task, or nil when the fixture is off.
    static func entry(for prompt: String) -> String? {
        guard let script = script(for: prompt), let origin = ChatWebTaskFixture.shared?.originURL?.absoluteString else { return nil }
        let path: String
        switch script {
        case .jobs, .stop: path = "/jobs/search?keyword=iOS"
        case .shop: path = "/shop/search?keyword=%E8%80%B3%E6%A9%9F"
        case .news: path = "/news"
        case .order: path = "/shop/cart"
        }
        return command(["action": "web_read_page", "url": origin + path])
    }

    /// The next command, from the prompt and how many steps already ran.
    static func next(messages: [ModelMessage]) async throws -> String {
        guard let start = messages.firstIndex(where: { $0.role == "assistant" && $0.content.hasPrefix("{\"action\":\"web_") }),
              start > 0, let script = script(for: messages[start - 1].content) else {
            return command(["action": "end_not_done", "reason": "fixture: unknown task"])
        }
        let step = messages[start...].filter { $0.role == "assistant" }.count
        let latest = messages.last?.content ?? ""
        switch (script, step) {
        case (.jobs, 1): return command(["action": "web_open_link", "linkID": 1])
        case (.jobs, _):
            return command(["action": "finish", "sources": [1, 2],
                            "answer": "WEB_TASK_JOBS_DONE：測試公司 1 月薪 50,000～65,000 元，需要 2 年以上 Swift 經驗。"])
        case (.shop, 1): return command(["action": "web_scroll", "direction": "down"])
        case (.shop, 2): return command(["action": "web_read_page"])
        case (.shop, _):
            return command(["action": "finish", "sources": [1],
                            "answer": latest.contains("型號 8") ? "WEB_TASK_SHOP_DONE 8" : "WEB_TASK_SHOP_DONE 4"])
        case (.news, 1): return command(["action": "web_open_link", "linkID": 1])
        case (.news, _):
            return command(["action": "finish", "sources": [2], "answer": "WEB_TASK_NEWS_DONE：重點一、重點二、重點三。"])
        case (.order, 1), (.order, 4): return command(["action": "web_observe"])
        case (.order, 2): return tap("送出訂單", in: messages)
        case (.order, 3):
            return command(["action": "request_confirmation", "kind": "order", "target": "送出訂單", "amount": "NT$ 1,290"])
        case (.order, 5):
            if messages.contains(where: { $0.role == "user" && $0.content.contains("\"allowed\":false") }) {
                return command(["action": "finish", "answer": "WEB_TASK_ORDER_REFUSED：沒有下單。"])
            }
            return tap("送出訂單", in: messages)
        case (.order, _):
            return command(["action": "finish", "sources": [1],
                            "answer": latest.contains("訂單成立") ? "WEB_TASK_ORDER_DONE：訂單成立，請自己付款 NT$ 1,290。" : "WEB_TASK_ORDER_NOT_DONE"])
        case (.stop, _):
            // Long enough for the test to press 停止; cancellation ends it.
            try await Task.sleep(nanoseconds: 120_000_000_000)
            return command(["action": "end_not_done", "reason": "fixture: not stopped"])
        }
    }

    /// Taps the control with this label from the latest web_observe result.
    private static func tap(_ label: String, in messages: [ModelMessage]) -> String {
        for message in messages.reversed() where message.role == "user" && message.content.contains("\"snapshotId\"") {
            guard let start = message.content.range(of: "<untrusted>\n"), let end = message.content.range(of: "\n</untrusted>"),
                  let object = try? JSONSerialization.jsonObject(with: Data(message.content[start.upperBound..<end.lowerBound].utf8)) as? [String: Any],
                  let snapshot = object["snapshotId"] as? String, let controls = object["controls"] as? [[String: Any]],
                  let ref = controls.first(where: { ($0["label"] as? String) == label })?["ref"] as? String else { break }
            return command(["action": "web_tap", "ref": ref, "snapshotId": snapshot])
        }
        return command(["action": "end_not_done", "reason": "fixture: no control " + label])
    }

    private static func command(_ fields: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data(), as: UTF8.self)
    }
}
#endif
