import Foundation

enum MemorySafety {
    static func normalized(_ text: String) -> String { text.precomposedStringWithCompatibilityMapping }

    /// Whether two memories say the same thing but for filler words (以後,
    /// 使用者的). Anything else that differs, such as a negation, a number or an
    /// added detail, makes them two memories.
    static func restates(_ first: String, _ second: String) -> Bool {
        func essence(_ text: String) -> String {
            var kept = String(normalized(text).lowercased().filter { $0.isLetter || $0.isNumber })
            for word in ["使用者", "用戶", "用户", "以後", "之後", "今後", "往後", "日後", "未來", "一律", "總是", "都", "請", "的", "我"] {
                kept = kept.replacingOccurrences(of: word, with: "")
            }
            return kept
        }
        let essential = essence(first)
        return essential.count >= 4 && essential == essence(second)
    }

    static func clean(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func keywords(_ words: [String]) throws -> [String] {
        guard words.count <= 8 else { throw MemoryError.invalidKeywords }
        var result: [String] = []
        for word in words.map(clean) where !word.isEmpty {
            guard word.utf16.count <= 30 else { throw MemoryError.invalidKeywords }
            if !result.contains(word) { result.append(word) }
        }
        return result
    }

    static func validate(content: String, keywords: [String], source: MemorySource) throws {
        guard !content.isEmpty, content.utf16.count <= 200,
              !content.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw MemoryError.invalidContent
        }
        _ = try self.keywords(keywords)
        guard ["manual", "user_said"].contains(source.type), source.at.timeIntervalSince1970.isFinite,
              (source.conversationID?.utf16.count ?? 0) <= 256,
              (source.quote?.utf16.count ?? 0) <= 1000 else { throw MemoryError.invalidState }
        if source.type == "user_said" {
            guard let quote = source.quote, normalized(quote).trimmingCharacters(in: .whitespacesAndNewlines).utf16.count >= 2 else {
                throw MemoryError.invalidState
            }
        }
        if ([content] + keywords + [source.quote].compactMap { $0 }).contains(where: sensitive) {
            throw MemoryError.sensitiveContent
        }
    }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func captures(_ pattern: String, _ text: String, group: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            let range = $0.range(at: group)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }
    }

    /// Best-effort exclusion, not a claim of complete secret detection: Android's SensitiveFilter
    /// (keyword, short gap, value, also reversed), keys, capability URLs and ID numbers. ASCII
    /// lookarounds, not \b: a Chinese character beside the value is a word character too, so
    /// 「金鑰是sk-…」, 「字號A1…」 and 「我的PIN是…」 had no boundary (live run of 287).
    static func sensitive(_ text: String) -> Bool {
        let value = normalized(text)
        let compact = value.components(separatedBy: .whitespacesAndNewlines).joined()
        let credentials = #"(?:(?<![A-Za-z0-9])(?:sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|AKIA[A-Z0-9]{16})|(?<![A-Za-z0-9])Bearer\s+\S+|(?<![A-Za-z0-9])eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|-----BEGIN [A-Z ]*PRIVATE KEY-----)"#
        let words = "密碼|密码|口令|驗證碼|验证码|校驗碼|校验码|動態碼|动态码|安全碼|安全码|安全問題|安全问题|password|passcode"
        let labels = "(?:" + words + #"|passwd|cvv|cvc|verification\s*code|security\s*code|security\s*question|one-?time\s*code|api[ _-]?key|access[ _-]?token|client[ _-]?secret)"#
        let short = #"(?<![A-Za-z])(?:pin|otp)(?![A-Za-z])"#
        let joins = #"[\s:：=,，]*(?:就是|是|為|为|叫做|叫|設成|設為|設定為|设为|设置为|改成|改為|改为|is|was|are)?[\s:：=]*"#
        let labeledSecret = labels + joins + #"(?:[A-Za-z0-9_./+\-]{4,}|[零〇一二三四五六七八九]{4,})"#
        let labeledPIN = short + #"\s*[12]?\s*(?:碼|码|code)?"# + joins + "[0-9]{4,}"
        let owner = #"\s*(?:就是|是|為|为)(?:我的|我|用戶的|用户的|使用者的)?[^A-Za-z0-9，。,.!！?？]{0,6}?"#
        let reversedSecret = "[A-Za-z0-9]{4,}" + owner + "(?:" + words + ")"
        let reversedPIN = "(?<![0-9])[0-9]{4,}" + owner + short
        if matches(credentials, value)
            || [labeledSecret, labeledPIN, reversedSecret, reversedPIN].contains(where: { matches($0, value) || matches($0, compact) }) { return true }
        // Capability URLs are credentials, even if their random secret has no familiar prefix.
        if matches(#"https?://[^\s]*(?:/webhook(?:/|\b)|[?&](?:key|token|secret|signature|api_key|access_token)=)"#, value)
            || matches(#"https?://[^\s/]+@"#, value) { return true }
        // Deliberately conservative around national identifiers; do not retain them.
        if matches(#"(?<![0-9])[1-9][0-9]{16}[0-9Xx](?![0-9A-Za-z])|(?<![A-Za-z0-9])[A-Z][1289][0-9]{8}(?![0-9A-Za-z])"#, value) { return true }
        for candidate in captures(#"(?<![0-9])[0-9](?:[ -]?[0-9]){12,18}(?![0-9])"#, value) {
            let digits = candidate.compactMap(\.wholeNumberValue)
            guard (13...19).contains(digits.count) else { continue }
            let sum = digits.reversed().enumerated().reduce(0) { sum, element in
                let digit = element.offset % 2 == 1 ? element.element * 2 : element.element
                return sum + (digit > 9 ? digit - 9 : digit)
            }
            if sum % 10 == 0 { return true }
        }
        return false
    }

    static func oneOff(_ text: String) -> Bool {
        matches(#"這次|这次|這一次|这一次|今天先|僅這次|仅这次|\bthis\s+time\b|\bjust\s+today\b|\bfor\s+now\b"#, text)
    }

    /// Words that are not a lasting fact about the user unless they ask for it to be
    /// remembered: a question, a task for this conversation (write, find, compare...),
    /// or a test or puzzle value (a code word, a secret phrase). Small models proposed
    /// such passages as memories (iPhone run of 283).
    static func notDurable(_ text: String) -> Bool {
        let asked = #"記住|記得|记住|记得|以後|以后|往後|往后|每次|一律|今後|今后|\bremember\b|\bfrom\s+now\s+on\b|\balways\b"#
        if matches(asked, text) { return false }
        if isQuestion(text) { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).subtracting(CharacterSet(charactersIn: "?？")))
        let task = #"^(?:請|请|麻煩|麻烦|幫我|帮我|可以|能不能|能否|please\b|can\s+you\b|could\s+you\b)|(?:幫我|帮我|請你|请你)\s*(?:寫|写|找|查|搜|比較|比较|翻譯|翻译|算|整理|列|說明|说明|分析|摘要|產生|生成|畫|画|做|讀|读|看)"#
        let puzzle = #"暗號|暗号|代號|代号|密語|密语|通關|通关|謎題|谜题|測試標記|测试标记|\bcode\s*word\b|\bsecret\s+(?:word|phrase)\b|\bpassphrase\b"#
        return matches(task, trimmed) || matches(puzzle, text)
    }

    /// Words that end as a question (?, ？, 嗎, 呢).
    static func isQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).subtracting(CharacterSet(charactersIn: "?？")))
        return trimmed.hasSuffix("?") || trimmed.hasSuffix("？") || trimmed.hasSuffix("嗎") || trimmed.hasSuffix("吗") || trimmed.hasSuffix("呢")
    }

    /// The words after an explicit 「請記住…」, 「記住：…」, 「記住我…」, "please remember …" or
    /// "remember that …" that opens the message: what the user asked to keep, up to the first
    /// question or task after it. nil when there is no such request, or it is a question.
    /// 「…，記得附上來源」, 「記住單字的方法」, "I can't remember the title" and "Remember the
    /// Titans cast" ask for nothing to be kept.
    static func explicitRemember(_ text: String) -> String? {
        let lead = #"(?:(?:嗨|哈囉|哈啰|你好|您好|妳好|對了|对了|另外|還有|还有|hi|hello|hey)[，,。.！!～~\s]+)?"#
        let polite = #"(?:(?:請|请|麻煩|麻烦|拜託|拜托|可以|能不能|幫我|帮我|替我|你|妳|您|要|先)\s*)+"#
        let mine = #"(?:我|以後|以后|往後|往后|每次|這件事|这件事)"#
        let chinese = #"^\s*"# + lead + "(?:" + polite + #"(?:記住|记住|(?:記得|记得)(?=\s*[：:，,、]?\s*"# + mine + "))"
            + #"|(?:記住|记住)(?=\s*(?:[：:，,、]|"# + mine + #"))|(?:記得|记得)(?=\s*[：:，,、]?\s*"# + mine + "))"
            + #"(?:這件事|这件事|一下|下來|下来|喔|哦)?\s*[：:，,、]?\s*"#
        let english = #"^\s*"# + lead + #"(?:(?:please\s+|(?:can|could|would)\s+you\s+(?:please\s+)?)remember\b(?!\s+(?:to|when|how)\b)(?:\s+(?:that|this)\b)?"#
            + #"|remember\b(?:\s+that\b|(?=\s*[:,])|(?=\s+(?:i|i['’]m|my|we|our|me)\b)))\s*[:,]?\s*"#
        guard let opening = text.range(of: chinese + "|" + english, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var kept: [String] = []
        for sentence in sentences(String(text[opening.upperBound...])) {
            let task = matches(#"^(?:另外|順便|顺便|然後|然后|接著|接着|also\b|then\b)"#, sentence)
            // A question ends the request even with 記得 in it (「…。你記得我喜歡什麼嗎？」).
            if task || isQuestion(sentence) || notDurable(sentence) { break }
            kept.append(sentence.trimmingCharacters(in: CharacterSet(charactersIn: "。.！!～~")))
        }
        let content = kept.joined(separator: matches(#"\p{Han}"#, text) ? "。" : ". ")
        // 「請記住這個」 alone names nothing to keep.
        let nothing = matches(#"^(?:這個|这个|那個|那个|這件事|这件事|那件事|它|this|that|it)$"#, content)
        return content.isEmpty || nothing ? nil : content
    }

    /// Sentences with their closing mark, so a question still reads as one.
    private static func sentences(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"[^。！!？?\n]+?(?:[。！!？?]+|\.(?=\s|$)|\n|$)"#) else { return [text] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    /// The answer declined to keep it (a secret, or it asked what was meant): the host keeps nothing either.
    static func declines(_ reply: String) -> Bool {
        matches(#"不幫|不帮|不會幫|不会帮|不能|無法|无法|不會把|不会把|不建議|不建议|不適合|不适合|不應|不应|抱歉|敏感|沒有(?:記|儲存|保存)|没有(?:记|储存|保存)|未能|未儲存|未保存|(?<![A-Za-z])(?:can['’]?t|cannot|won['’]?t|unable|sorry|sensitive|not\s+(?:able|save|saved|store|stored|remember|keep))(?![A-Za-z])"#, reply)
    }

    /// Content that only reports what the user asked for this time.
    static func describesRequest(_ content: String) -> Bool {
        matches(#"用戶請求|用户请求|使用者請求|用戶要求|用户要求|使用者要求|\bthe\s+user\s+(?:asked|requested|wants\s+(?:me|the\s+assistant)\s+to)\b"#, content)
    }

    static func forgetRequested(quote: String, fullMessages: [String]) -> Bool {
        let positive = #"忘掉|忘記|忘记|別記|别记|不要記|不要记|不用記|不用记|刪除|删除|刪掉|删掉|\b(?:forget|delete|remove)\b"#
        let negative = #"(?:不|別|别|無需|无需|不用|不必|不要|不能|不准|禁止|不想)\s*(?:要|用|再|去)?\s*(?:刪|删|忘)|\b(?:do\s+not|don't|don’t|dont|never|not\s+to)\s+(?:delete|forget|remove)\b"#
        return matches(positive, quote) && !fullMessages.contains { matches(negative, $0) }
    }

    static func deniesUpdate(_ messages: [String]) -> Bool {
        let pattern = #"(?:不|別|别|不要|不用|不必|不能|不准|禁止|無需|无需)\s*(?:再|去)?\s*(?:修改|更新|更正|改成|改為|改为|改掉)|\b(?:do\s+not|don't|don’t|never|not\s+to)\s+(?:update|change|edit|correct)\b"#
        return messages.contains { matches(pattern, $0) }
    }

    /// A quoted substring alone is insufficient: concrete values must also occur in
    /// the user's statements. This heuristic cannot prove arbitrary paraphrases.
    static func grounded(_ value: String, utterances: [String]) -> Bool {
        let sources = utterances.map { normalized($0).lowercased() }
        let text = normalized(value)
        let specifics = captures(#"[「『“"]([^「」『』“”"\n]+)[」』”"]"#, text, group: 1)
            + captures(#"[0-9]+|[A-Za-z][A-Za-z0-9._-]{2,}"#, text)
            + captures(#"\p{Han}{2}(?:小區|小区|大廈|大厦|廣場|广场|公寓|花園|花园|單元|单元|路|街|巷|弄|鎮|镇|村|號|号|樓|楼|棟|栋|室|區|区|縣|县|市|省|園|园|苑|城|道|里|灣|湾)"#, text)
        let grammar: Set<String> = ["the", "user", "users", "prefers", "likes", "dislikes", "lives", "has", "their", "they", "are", "and", "with", "without", "always", "wants", "uses"]
        return specifics.allSatisfy { specific in
            let needle = specific.lowercased()
            return grammar.contains(needle) || sources.contains { $0.contains(needle) }
        }
    }
}
