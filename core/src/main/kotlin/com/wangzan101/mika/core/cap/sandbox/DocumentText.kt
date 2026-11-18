package com.wangzan101.mika.core.cap.sandbox

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.nio.charset.Charset
import java.util.zip.DataFormatException
import java.util.zip.Inflater
import java.util.zip.ZipInputStream
import kotlin.math.abs

/**
 * 文档的文字层,给只有文件的工作区(商店版:没有命令行,跑不了 PDF 脚本)的 read_file 用:
 * PDF 按页、Word 按段落、Excel 按工作表、PowerPoint 按投影片取出文字。
 * 只读字节:不执行文档里的任何东西,也不画页面。扫描出来的 PDF、加了密的、旧的二进制格式照实说读不了。
 */
internal object DocumentText {
    /** [unit]:结果里计数的单位(pages、paragraphs、sheets、slides);[legacy] 是读不了的旧二进制格式。 */
    enum class Type(val mime: String, val unit: String, val legacy: Boolean = false) {
        Pdf("application/pdf", "pages"),
        Docx("application/vnd.openxmlformats-officedocument.wordprocessingml.document", "paragraphs"),
        Xlsx("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "sheets"),
        Pptx("application/vnd.openxmlformats-officedocument.presentationml.presentation", "slides"),
        Doc("application/msword", "pages", legacy = true),
        Xls("application/vnd.ms-excel", "sheets", legacy = true),
        Ppt("application/vnd.ms-powerpoint", "slides", legacy = true),
    }

    fun typeOf(ext: String): Type? = when (ext.lowercase()) {
        "pdf" -> Type.Pdf
        "docx", "docm" -> Type.Docx
        "xlsx", "xlsm" -> Type.Xlsx
        "pptx", "pptm" -> Type.Pptx
        "doc" -> Type.Doc
        "xls" -> Type.Xls
        "ppt" -> Type.Ppt
        else -> null
    }

    sealed interface Result {
        /** 整份文字([utf8],UTF-8);[count] 是 [unit] 的个数。 */
        class Text(val utf8: ByteArray, val unit: String, val count: Int) : Result {
            val text: String get() = String(utf8, Charsets.UTF_8)
        }
        /** 读不了:[code] 是给模型的错误码,[message] 说为什么、接下来怎么办。 */
        class Unreadable(val code: String, val message: String) : Result
    }

    /** 取出的文字最多这么多字(UTF-8 约几 MB);再长的截断并说明。 */
    const val MAX_CHARS = 2_000_000
    private const val TIME_MS = 30_000L

    const val NO_TEXT = "No text could be read from this PDF. It is probably a scan or photos of pages (or its fonts carry no text). " +
        "Tell the user it cannot be read as text here, and ask for photos or screenshots of the pages that matter."
    const val ENCRYPTED = "This PDF is encrypted, so its text cannot be read here. Ask the user for a copy without a password or protection, " +
        "or for photos or screenshots of the pages that matter."
    const val OLD_FORMAT = "This is an older Office format (.doc, .xls or .ppt) that cannot be read here. " +
        "Ask the user to send it as a PDF or as a newer .docx, .xlsx or .pptx file."
    const val DAMAGED = "This file could not be read as a document: it may be damaged, password-protected or not what its name says."
    const val EMPTY = "No text was found in this document."
    const val TOO_SLOW = "Reading this document took too long. Ask the user for a smaller file, or for the pages that matter."
    const val TOO_LARGE = "This document is too large to read here. Ask the user for a smaller file, or for the pages that matter."
    const val TRUNCATED = "(The text stops here: the document is longer than can be read at once.)"

    fun extract(bytes: ByteArray, type: Type, timeMs: Long = TIME_MS): Result {
        if (type.legacy) return Result.Unreadable("document_old_format", OLD_FORMAT)
        val deadline = System.nanoTime() + timeMs * 1_000_000
        return try {
            when (type) {
                Type.Pdf -> Pdf.extract(bytes, deadline)
                Type.Docx -> Ooxml.docx(bytes, deadline)
                Type.Xlsx -> Ooxml.xlsx(bytes, deadline)
                Type.Pptx -> Ooxml.pptx(bytes, deadline)
                else -> Result.Unreadable("document_old_format", OLD_FORMAT)
            }
        } catch (e: TimeUp) {
            Result.Unreadable("document_too_slow", TOO_SLOW)
        } catch (e: TooLarge) {
            Result.Unreadable("file_too_large", TOO_LARGE)
        } catch (e: OutOfMemoryError) {
            Result.Unreadable("file_too_large", TOO_LARGE)
        } catch (e: Exception) {
            Result.Unreadable("document_unreadable", DAMAGED)
        }
    }

    internal class TimeUp : RuntimeException(null, null, false, false)
    internal class TooLarge : RuntimeException(null, null, false, false)

    internal fun checkTime(deadline: Long) {
        if (System.nanoTime() > deadline) throw TimeUp()
    }

    /** 去掉控制字符和私用区的字(符号字体),合并多余的空格和空行;最多 [MAX_CHARS] 字。 */
    internal fun clean(s: String): String {
        val sb = StringBuilder(minOf(s.length, MAX_CHARS))
        for (ch in s) {
            if (sb.length >= MAX_CHARS) break
            when {
                ch == '\r' -> sb.append('\n')
                ch == '\t' || ch == '\n' -> sb.append(ch)
                ch == '\u00A0' -> sb.append(' ')
                ch.code < 0x20 || ch.code == 0x7F -> {}
                ch.code in 0xE000..0xF8FF -> {}
                ch == '\uFFFE' || ch == '\uFFFF' -> {}
                else -> sb.append(ch)
            }
        }
        return sb.toString()
            .replace(SPACES, " ")
            .replace(LINE_END, "\n")
            .replace(BLANK_LINES, "\n\n")
            .trim()
    }

    private val SPACES = Regex(" {2,}")
    private val LINE_END = Regex("[ \\t]+\n")
    private val BLANK_LINES = Regex("\n{3,}")

    /** 有没有可读的字(空白以外的字符)。 */
    internal fun hasText(s: String): Boolean = s.any { !it.isWhitespace() }

    internal fun text(sections: String, unit: String, count: Int, truncated: Boolean): Result.Text {
        val body = if (truncated) "$sections\n\n$TRUNCATED" else sections
        return Result.Text(body.toByteArray(Charsets.UTF_8), unit, count)
    }
}

// ---------- PDF ----------

private sealed interface PdfObj
private class PNum(val v: Double) : PdfObj
private class PStr(val bytes: ByteArray) : PdfObj
private class PName(val v: String) : PdfObj
private class PArr(val items: List<PdfObj>) : PdfObj
private class PDict(val map: Map<String, PdfObj>) : PdfObj {
    operator fun get(key: String): PdfObj? = map[key]
}
private class PRef(val num: Int) : PdfObj
/** 关键字:内容流里的操作符,以及 true、false、null 和读不懂的字节。 */
private class PWord(val v: String) : PdfObj
/** 流对象:数据在原文件的 [start, end) 里(不另复制一份)。 */
private class PStream(val dict: PDict, val start: Int, val end: Int) : PdfObj

private fun isSpace(c: Int) = c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32
private fun isDelim(c: Int) = c == '('.code || c == ')'.code || c == '<'.code || c == '>'.code || c == '['.code ||
    c == ']'.code || c == '{'.code || c == '}'.code || c == '/'.code || c == '%'.code
private fun hexValue(c: Int): Int = when (c) {
    in '0'.code..'9'.code -> c - '0'.code
    in 'a'.code..'f'.code -> c - 'a'.code + 10
    in 'A'.code..'F'.code -> c - 'A'.code + 10
    else -> -1
}

/** PDF 的词法:对象(数、字符串、名字、数组、字典、引用)和关键字。读不懂的字节当成一个关键字跳过,保证一直往前走。 */
private class PdfLexer(private val b: ByteArray, var pos: Int = 0, private val end: Int = b.size) {
    private fun at(i: Int): Int = if (i in 0 until end) b[i].toInt() and 0xFF else -1

    fun skipSpace() {
        while (pos < end) {
            val c = at(pos)
            if (isSpace(c)) pos++
            else if (c == '%'.code) { while (pos < end && at(pos) != 10 && at(pos) != 13) pos++ }
            else return
        }
    }

    fun startsWith(word: String): Boolean {
        if (pos + word.length > end) return false
        for (k in word.indices) if (at(pos + k) != word[k].code) return false
        return true
    }

    /** 下一个对象;到末尾为 null。[refs] 时把 `n g R` 合成引用(内容流里没有引用)。 */
    fun next(refs: Boolean, depth: Int = 0): PdfObj? {
        skipSpace()
        if (pos >= end) return null
        val c = at(pos)
        if (depth > 48) { pos++; return PWord("") }
        return when {
            c == '/'.code -> name()
            c == '('.code -> literal()
            c == '['.code -> { pos++; PArr(items(refs, depth)) }
            c == '<'.code && at(pos + 1) == '<'.code -> { pos += 2; dict(refs, depth) }
            c == '<'.code -> hex()
            isDelim(c) -> { pos++; PWord(c.toChar().toString()) }
            else -> word(refs)
        }
    }

    private fun items(refs: Boolean, depth: Int): List<PdfObj> {
        val out = ArrayList<PdfObj>()
        while (true) {
            skipSpace()
            if (pos >= end) break
            if (at(pos) == ']'.code) { pos++; break }
            val o = next(refs, depth + 1) ?: break
            out += o
        }
        return out
    }

    private fun dict(refs: Boolean, depth: Int): PDict {
        val map = HashMap<String, PdfObj>()
        while (true) {
            skipSpace()
            if (pos >= end) break
            if (at(pos) == '>'.code && at(pos + 1) == '>'.code) { pos += 2; break }
            val key = next(refs, depth + 1) ?: break
            if (key !is PName) continue
            skipSpace()
            if (at(pos) == '>'.code && at(pos + 1) == '>'.code) { pos += 2; break }
            val value = next(refs, depth + 1) ?: break
            map[key.v] = value
        }
        return PDict(map)
    }

    private fun word(refs: Boolean): PdfObj {
        val start = pos
        while (pos < end) {
            val c = at(pos)
            if (isSpace(c) || isDelim(c)) break
            pos++
        }
        if (pos == start) { pos++; return PWord("") }
        val text = String(b, start, pos - start, Charsets.ISO_8859_1)
        val first = text[0]
        if (!(first.isDigit() || first == '-' || first == '+' || first == '.')) return PWord(text)
        val number = text.toDoubleOrNull() ?: return PWord(text)
        if (refs && number >= 0 && text.all { it.isDigit() }) reference(number.toInt())?.let { return it }
        return PNum(number)
    }

    /** 刚读了一个非负整数:后面跟着 `g R` 时是引用。 */
    private fun reference(num: Int): PRef? {
        val save = pos
        skipSpace()
        val genStart = pos
        while (pos < end && at(pos) in '0'.code..'9'.code) pos++
        if (pos > genStart && pos < end && isSpace(at(pos))) {
            skipSpace()
            if (at(pos) == 'R'.code && (pos + 1 >= end || isSpace(at(pos + 1)) || isDelim(at(pos + 1)))) {
                pos++
                return PRef(num)
            }
        }
        pos = save
        return null
    }

    private fun name(): PName {
        pos++
        val sb = StringBuilder()
        while (pos < end) {
            val c = at(pos)
            if (isSpace(c) || isDelim(c)) break
            pos++
            if (c == '#'.code && hexValue(at(pos)) >= 0 && hexValue(at(pos + 1)) >= 0) {
                sb.append((hexValue(at(pos)) * 16 + hexValue(at(pos + 1))).toChar())
                pos += 2
            } else sb.append(c.toChar())
        }
        return PName(sb.toString())
    }

    private fun literal(): PStr {
        pos++
        val out = ByteArrayOutputStream()
        var depth = 1
        while (pos < end) {
            val c = at(pos++)
            when (c) {
                '('.code -> { depth++; out.write(c) }
                ')'.code -> { depth--; if (depth == 0) return PStr(out.toByteArray()); out.write(c) }
                '\\'.code -> escape(out)
                else -> out.write(c)
            }
        }
        return PStr(out.toByteArray())
    }

    private fun escape(out: ByteArrayOutputStream) {
        val e = at(pos++)
        when (e) {
            'n'.code -> out.write(10)
            'r'.code -> out.write(13)
            't'.code -> out.write(9)
            'b'.code -> out.write(8)
            'f'.code -> out.write(12)
            13 -> if (at(pos) == 10) pos++
            10, -1 -> {}
            in '0'.code..'7'.code -> {
                var v = e - '0'.code
                var k = 0
                while (k < 2 && at(pos) in '0'.code..'7'.code) { v = v * 8 + (at(pos) - '0'.code); pos++; k++ }
                out.write(v and 0xFF)
            }
            else -> out.write(e)
        }
    }

    private fun hex(): PStr {
        pos++
        val out = ByteArrayOutputStream()
        var high = -1
        while (pos < end) {
            val c = at(pos++)
            if (c == '>'.code) break
            val v = hexValue(c)
            if (v < 0) continue
            if (high < 0) high = v else { out.write(high * 16 + v); high = -1 }
        }
        if (high >= 0) out.write(high * 16)
        return PStr(out.toByteArray())
    }

    /** 内容流里的内嵌图片(BI … ID 数据 EI):跳过数据。 */
    fun skipInlineImage() {
        while (true) {
            val o = next(refs = false) ?: return
            if (o is PWord && o.v == "ID") break
        }
        if (pos < end) pos++
        while (pos < end) {
            if (at(pos) == 'E'.code && at(pos + 1) == 'I'.code && isSpace(at(pos - 1)) &&
                (pos + 2 >= end || isSpace(at(pos + 2)) || isDelim(at(pos + 2)))) {
                pos += 2
                return
            }
            pos++
        }
    }
}

/** 字体把字符串里的码换成字:ToUnicode 表优先,其次单字节字体的编码表,或预定义的中日韩编码。 */
private class PdfFont(
    private val cmap: ToUnicode?,
    private val simple: Array<String?>?,
    private val charset: Charset?,
) {
    fun decode(bytes: ByteArray): String = when {
        cmap != null -> cmap.decode(bytes, simple)
        charset != null -> String(bytes, charset)
        simple != null -> buildString { for (x in bytes) simple[x.toInt() and 0xFF]?.let { append(it) } }
        else -> ""
    }
}

/** ToUnicode CMap:码的长度(codespacerange)、单个码(bfchar)、码段(bfrange)。 */
private class ToUnicode(
    private val spaces: List<Triple<Int, ByteArray, ByteArray>>,
    private val singles: Map<Long, String>,
    private val ranges: List<BfRange>,
    private val defaultLength: Int,
) {
    class BfRange(val length: Int, val low: Long, val high: Long, val base: String?, val list: List<String>?)

    private val lengths = spaces.map { it.first }.distinct().sorted()

    fun decode(bytes: ByteArray, fallback: Array<String?>?): String {
        val sb = StringBuilder()
        var i = 0
        while (i < bytes.size) {
            val len = minOf(codeLength(bytes, i), bytes.size - i)
            var code = 0L
            for (k in 0 until len) code = (code shl 8) or (bytes[i + k].toLong() and 0xFF)
            val s = singles[key(len, code)] ?: range(len, code) ?: if (len == 1) fallback?.get(code.toInt()) else null
            if (s != null) sb.append(s)
            i += len
        }
        return sb.toString()
    }

    private fun codeLength(bytes: ByteArray, at: Int): Int {
        for (len in lengths) {
            if (at + len > bytes.size) continue
            val fits = spaces.any { (l, lo, hi) ->
                l == len && (0 until len).all { k ->
                    val v = bytes[at + k].toInt() and 0xFF
                    v >= (lo[k].toInt() and 0xFF) && v <= (hi[k].toInt() and 0xFF)
                }
            }
            if (fits) return len
        }
        return lengths.firstOrNull() ?: defaultLength
    }

    private fun range(len: Int, code: Long): String? {
        val r = ranges.firstOrNull { it.length == len && code >= it.low && code <= it.high } ?: return null
        val offset = (code - r.low).toInt()
        r.list?.let { return it.getOrNull(offset) }
        val base = r.base ?: return null
        if (base.isEmpty()) return null
        val chars = base.toCharArray()
        chars[chars.size - 1] = (chars[chars.size - 1].code + offset).toChar()
        return String(chars)
    }

    companion object {
        fun key(len: Int, code: Long): Long = (len.toLong() shl 40) or code

        fun parse(data: ByteArray, defaultLength: Int): ToUnicode {
            val lexer = PdfLexer(data)
            val spaces = ArrayList<Triple<Int, ByteArray, ByteArray>>()
            val singles = HashMap<Long, String>()
            val ranges = ArrayList<BfRange>()
            val pending = ArrayList<PdfObj>()
            var mode = 0
            var lengthSeen = 0
            while (true) {
                val o = lexer.next(refs = false) ?: break
                if (o is PWord) {
                    mode = when (o.v) {
                        "begincodespacerange" -> 1
                        "beginbfchar" -> 2
                        "beginbfrange" -> 3
                        else -> 0
                    }
                    pending.clear()
                    continue
                }
                if (mode == 0) continue
                pending += o
                when (mode) {
                    1 -> if (pending.size == 2) {
                        val lo = (pending[0] as? PStr)?.bytes
                        val hi = (pending[1] as? PStr)?.bytes
                        if (lo != null && hi != null && lo.size == hi.size && lo.size in 1..4) spaces += Triple(lo.size, lo, hi)
                        pending.clear()
                    }
                    2 -> if (pending.size == 2) {
                        val src = (pending[0] as? PStr)?.bytes
                        val dst = target(pending[1])
                        if (src != null && src.size in 1..4 && dst != null) {
                            singles[key(src.size, number(src))] = dst
                            lengthSeen = src.size
                        }
                        pending.clear()
                    }
                    3 -> if (pending.size == 3) {
                        val lo = (pending[0] as? PStr)?.bytes
                        val hi = (pending[1] as? PStr)?.bytes
                        if (lo != null && hi != null && lo.size == hi.size && lo.size in 1..4) {
                            val dst = pending[2]
                            val list = (dst as? PArr)?.items?.map { target(it).orEmpty() }
                            ranges += BfRange(lo.size, number(lo), number(hi), if (list == null) target(dst) else null, list)
                            lengthSeen = lo.size
                        }
                        pending.clear()
                    }
                }
            }
            return ToUnicode(spaces, singles, ranges, if (lengthSeen > 0) lengthSeen else defaultLength)
        }

        private fun number(b: ByteArray): Long {
            var v = 0L
            for (x in b) v = (v shl 8) or (x.toLong() and 0xFF)
            return v
        }

        /** 目标是 UTF-16BE 的字(也可能是字形名)。 */
        private fun target(o: PdfObj): String? = when (o) {
            is PStr -> if (o.bytes.size >= 2) String(o.bytes, Charsets.UTF_16BE) else o.bytes.firstOrNull()?.let { (it.toInt() and 0xFF).toChar().toString() }
            is PName -> Glyphs.unicode(o.v)
            else -> null
        }
    }
}

/** 常见的字形名(Adobe Glyph List 的一部分)和 uniXXXX、uXXXX 写法。 */
private object Glyphs {
    private val names = mapOf(
        "space" to " ", "exclam" to "!", "quotedbl" to "\"", "numbersign" to "#", "dollar" to "$", "percent" to "%",
        "ampersand" to "&", "quotesingle" to "'", "quoteright" to "\u2019", "quoteleft" to "\u2018", "parenleft" to "(",
        "parenright" to ")", "asterisk" to "*", "plus" to "+", "comma" to ",", "hyphen" to "-", "minus" to "\u2212",
        "period" to ".", "slash" to "/", "zero" to "0", "one" to "1", "two" to "2", "three" to "3", "four" to "4",
        "five" to "5", "six" to "6", "seven" to "7", "eight" to "8", "nine" to "9", "colon" to ":", "semicolon" to ";",
        "less" to "<", "equal" to "=", "greater" to ">", "question" to "?", "at" to "@", "bracketleft" to "[",
        "backslash" to "\\", "bracketright" to "]", "asciicircum" to "^", "underscore" to "_", "grave" to "`",
        "braceleft" to "{", "bar" to "|", "braceright" to "}", "asciitilde" to "~", "bullet" to "\u2022",
        "endash" to "\u2013", "emdash" to "\u2014", "quotedblleft" to "\u201C", "quotedblright" to "\u201D",
        "quotesinglbase" to "\u201A", "quotedblbase" to "\u201E", "ellipsis" to "\u2026", "fi" to "fi", "fl" to "fl",
        "ff" to "ff", "ffi" to "ffi", "ffl" to "ffl", "dagger" to "\u2020", "daggerdbl" to "\u2021", "trademark" to "\u2122",
        "copyright" to "\u00A9", "registered" to "\u00AE", "degree" to "\u00B0", "section" to "\u00A7", "paragraph" to "\u00B6",
        "periodcentered" to "\u00B7", "guillemotleft" to "\u00AB", "guillemotright" to "\u00BB", "nbspace" to " ",
        "nonbreakingspace" to " ", "sterling" to "\u00A3", "yen" to "\u00A5", "Euro" to "\u20AC", "cent" to "\u00A2",
        "multiply" to "\u00D7", "divide" to "\u00F7", "plusminus" to "\u00B1", "eacute" to "\u00E9", "egrave" to "\u00E8",
        "aacute" to "\u00E1", "agrave" to "\u00E0", "adieresis" to "\u00E4", "odieresis" to "\u00F6", "udieresis" to "\u00FC",
        "ccedilla" to "\u00E7", "ntilde" to "\u00F1", "germandbls" to "\u00DF",
    )

    fun unicode(name: String): String? {
        val base = name.substringBefore('.')
        if (base.isEmpty()) return null
        if ('_' in base) return base.split('_').map { unicode(it) ?: return null }.joinToString("")
        names[base]?.let { return it }
        if (base.length == 1 && base[0].isLetter()) return base
        if (base.startsWith("uni") && base.length >= 7 && (base.length - 3) % 4 == 0) {
            val sb = StringBuilder()
            for (k in 3 until base.length step 4) sb.append(base.substring(k, k + 4).toIntOrNull(16)?.toChar() ?: return null)
            return sb.toString()
        }
        if (base.startsWith("u") && base.length in 5..7) {
            val cp = base.substring(1).toIntOrNull(16) ?: return null
            return if (Character.isValidCodePoint(cp)) String(Character.toChars(cp)) else null
        }
        return null
    }
}

private object Pdf {
    private const val MAX_PAGES = 2000
    private const val MAX_STREAM = 64 shl 20
    private const val MAX_DECODED = 256L shl 20

    fun extract(bytes: ByteArray, deadline: Long): DocumentText.Result {
        val doc = PdfDocument(bytes, deadline)
        if (doc.encrypted) return DocumentText.Result.Unreadable("document_encrypted", DocumentText.ENCRYPTED)
        val pages = doc.pages()
        if (pages.isEmpty()) return DocumentText.Result.Unreadable("document_unreadable", DocumentText.DAMAGED)
        val sb = StringBuilder()
        var any = false
        var truncated = false
        for ((i, page) in pages.withIndex()) {
            if (sb.length >= DocumentText.MAX_CHARS) { truncated = true; break }
            val text = DocumentText.clean(doc.text(page.first, page.second))
            if (i > 0) sb.append("\n\n")
            sb.append("--- page ").append(i + 1).append(" ---\n")
            if (DocumentText.hasText(text)) { any = true; sb.append(text) } else sb.append("(no text on this page)")
        }
        if (!any) return DocumentText.Result.Unreadable("document_no_text", DocumentText.NO_TEXT)
        return DocumentText.text(sb.toString(), "pages", pages.size, truncated)
    }

    private class PdfDocument(private val b: ByteArray, private val deadline: Long) {
        private val objects = HashMap<Int, PdfObj>()
        private val trailers = ArrayList<PDict>()
        private val fonts = HashMap<PDict, PdfFont>()
        private var decoded = 0L
        var encrypted = false
            private set

        init {
            scan()
            expandObjectStreams()
            encrypted = trailers.any { it["Encrypt"] != null }
        }

        private fun at(i: Int): Int = if (i in b.indices) b[i].toInt() and 0xFF else -1

        private fun indexOf(word: ByteArray, from: Int): Int {
            var i = maxOf(from, 0)
            val last = b.size - word.size
            while (i <= last) {
                if (b[i] == word[0]) {
                    var k = 1
                    while (k < word.size && b[i + k] == word[k]) k++
                    if (k == word.size) return i
                }
                i++
            }
            return -1
        }

        /** 找出所有「n g obj」开头的对象;后出现的同号对象(增量更新)盖掉前面的。 */
        private fun scan() {
            var i = 0
            while (true) {
                DocumentText.checkTime(deadline)
                val k = indexOf(OBJ, i)
                if (k < 0) break
                i = k + 3
                if (k + 3 < b.size && !isSpace(at(k + 3)) && !isDelim(at(k + 3))) continue
                val num = numberBefore(k) ?: continue
                val lexer = PdfLexer(b, k + 3)
                val parsed = try { lexer.next(refs = true) } catch (e: DocumentText.TimeUp) { throw e } catch (e: Exception) { null }
                val o = parsed ?: continue
                if (o is PDict) {
                    lexer.skipSpace()
                    if (lexer.startsWith("stream")) {
                        val range = streamRange(o, afterEol(lexer.pos + 6)) ?: continue
                        objects[num] = PStream(o, range.first, range.second)
                        if (o["Type"].let { it is PName && it.v == "XRef" }) trailers += o
                        i = maxOf(i, range.third)
                        continue
                    }
                }
                objects[num] = o
            }
            var t = 0
            while (true) {
                val k = indexOf(TRAILER, t)
                if (k < 0) break
                t = k + TRAILER.size
                val dict = try { PdfLexer(b, t).next(refs = true) } catch (e: Exception) { null }
                if (dict is PDict) trailers += dict
            }
        }

        /** 「obj」前面是「对象号 代号 」时给出对象号。 */
        private fun numberBefore(k: Int): Int? {
            var p = k - 1
            if (p < 0 || !isSpace(at(p))) return null
            while (p >= 0 && isSpace(at(p))) p--
            val genEnd = p
            while (p >= 0 && at(p) in '0'.code..'9'.code) p--
            if (p == genEnd || p < 0 || !isSpace(at(p))) return null
            while (p >= 0 && isSpace(at(p))) p--
            val numEnd = p
            while (p >= 0 && at(p) in '0'.code..'9'.code) p--
            if (p == numEnd || numEnd - p > 9) return null
            if (p >= 0 && !isSpace(at(p)) && !isDelim(at(p))) return null
            return String(b, p + 1, numEnd - p, Charsets.ISO_8859_1).toIntOrNull()
        }

        private fun afterEol(p: Int): Int = when {
            at(p) == 13 && at(p + 1) == 10 -> p + 2
            at(p) == 10 || at(p) == 13 -> p + 1
            else -> p
        }

        /** 流数据的 [起, 止) 和 endstream 之后的位置:/Length 对得上就用它,否则找 endstream。 */
        private fun streamRange(dict: PDict, start: Int): Triple<Int, Int, Int>? {
            val length = (dict["Length"] as? PNum)?.v?.toInt()
            if (length != null && length >= 0 && start + length <= b.size) {
                var q = start + length
                while (q < b.size && isSpace(at(q))) q++
                if (startsWithAt(q, ENDSTREAM)) return Triple(start, start + length, q + ENDSTREAM.size)
            }
            val e = indexOf(ENDSTREAM, start)
            if (e < 0) return null
            var dataEnd = e
            if (dataEnd > start && at(dataEnd - 1) == 10) dataEnd--
            if (dataEnd > start && at(dataEnd - 1) == 13) dataEnd--
            return Triple(start, dataEnd, e + ENDSTREAM.size)
        }

        private fun startsWithAt(p: Int, word: ByteArray): Boolean {
            if (p < 0 || p + word.size > b.size) return false
            for (k in word.indices) if (b[p + k] != word[k]) return false
            return true
        }

        /** 对象流(/Type /ObjStm)里压着的对象:没在文件里直接出现过的才放进来。 */
        private fun expandObjectStreams() {
            val streams = objects.values.filterIsInstance<PStream>().filter { s -> s.dict["Type"].let { it is PName && it.v == "ObjStm" } }
            for (s in streams) {
                DocumentText.checkTime(deadline)
                val data = decode(s) ?: continue
                val n = (resolve(s.dict["N"]) as? PNum)?.v?.toInt() ?: continue
                val first = (resolve(s.dict["First"]) as? PNum)?.v?.toInt() ?: continue
                if (n <= 0 || first < 0 || first > data.size) continue
                val header = PdfLexer(data, 0, first)
                val entries = ArrayList<Pair<Int, Int>>()
                repeat(minOf(n, 100_000)) {
                    val num = (header.next(refs = false) as? PNum)?.v?.toInt() ?: return@repeat
                    val off = (header.next(refs = false) as? PNum)?.v?.toInt() ?: return@repeat
                    entries += num to off
                }
                for ((num, off) in entries) {
                    if (num in objects || first + off >= data.size || off < 0) continue
                    val parsed = try { PdfLexer(data, first + off).next(refs = true) } catch (e: Exception) { null }
                    if (parsed != null) objects[num] = parsed
                }
            }
        }

        fun resolve(o: PdfObj?): PdfObj? {
            var x = o
            var hops = 0
            while (x is PRef && hops++ < 16) x = objects[x.num]
            return if (x is PRef) null else x
        }

        private fun type(d: PDict): String? = (resolve(d["Type"]) as? PName)?.v

        /** 页树里的页(按阅读顺序)和每页的资源(没有自己的就用上一层的);页树坏了按对象号找 /Type /Page。 */
        fun pages(): List<Pair<PDict, PDict?>> {
            val out = ArrayList<Pair<PDict, PDict?>>()
            val catalog = trailers.asReversed().firstNotNullOfOrNull { resolve(it["Root"]) as? PDict }
                ?: objects.values.filterIsInstance<PDict>().firstOrNull { type(it) == "Catalog" }
            (catalog?.let { resolve(it["Pages"]) } as? PDict)?.let { walk(it, null, out, HashSet(), 0) }
            if (out.isEmpty()) {
                for (num in objects.keys.sorted()) {
                    val d = objects[num] as? PDict ?: continue
                    if (type(d) == "Page") out += d to (resolve(d["Resources"]) as? PDict)
                    if (out.size >= MAX_PAGES) break
                }
            }
            return out
        }

        private fun walk(node: PDict, inherited: PDict?, out: MutableList<Pair<PDict, PDict?>>, seen: MutableSet<PDict>, depth: Int) {
            if (depth > 64 || out.size >= MAX_PAGES || !seen.add(node)) return
            val resources = (resolve(node["Resources"]) as? PDict) ?: inherited
            val kids = resolve(node["Kids"]) as? PArr
            if (kids != null && type(node) != "Page") {
                for (kid in kids.items) (resolve(kid) as? PDict)?.let { walk(it, resources, out, seen, depth + 1) }
            } else out += node to resources
        }

        /** 一页的字:内容流里的文字操作(连同表单 XObject 里的),按位置换行、隔开词。 */
        fun text(page: PDict, resources: PDict?): String {
            val sink = TextSink()
            val streams = when (val c = resolve(page["Contents"])) {
                is PStream -> listOf(c)
                is PArr -> c.items.mapNotNull { resolve(it) as? PStream }
                else -> emptyList()
            }
            val data = ByteArrayOutputStream()
            for (s in streams) decode(s)?.let { data.write(it); data.write(10) }
            if (data.size() > 0) interpret(data.toByteArray(), resources, sink, 0, HashSet())
            return sink.result()
        }

        private fun interpret(data: ByteArray, resources: PDict?, sink: TextSink, depth: Int, forms: MutableSet<PStream>) {
            val lexer = PdfLexer(data)
            val operands = ArrayList<PdfObj>()
            var font: PdfFont? = null
            var size = 1.0
            var leading = 0.0
            // 文字的行矩阵;只为判断换没换行
            var a = 1.0; var bb = 0.0; var c = 0.0; var d = 1.0; var e = 0.0; var f = 0.0
            var lastY = Double.NaN
            var moved = false
            fun move(tx: Double, ty: Double) {
                e += tx * a + ty * c
                f += tx * bb + ty * d
                moved = true
            }
            fun show(o: PdfObj?) {
                val s = o as? PStr ?: return
                val text = font?.decode(s.bytes) ?: String(s.bytes, Charsets.ISO_8859_1)
                if (text.isEmpty()) return
                val threshold = maxOf(1.0, abs(size * d) * 0.5)
                if (!lastY.isNaN() && abs(f - lastY) > threshold) sink.newline() else if (moved) sink.gap()
                lastY = f
                moved = false
                sink.text(text)
            }
            fun num(k: Int): Double = (operands.getOrNull(operands.size - k) as? PNum)?.v ?: 0.0
            while (true) {
                DocumentText.checkTime(deadline)
                val o = lexer.next(refs = false) ?: break
                if (o !is PWord) {
                    if (operands.size < 64) operands += o
                    continue
                }
                when (o.v) {
                    "BT" -> { a = 1.0; bb = 0.0; c = 0.0; d = 1.0; e = 0.0; f = 0.0; moved = true }
                    "Tf" -> {
                        font = (operands.getOrNull(operands.size - 2) as? PName)?.let { fontFor(resources, it.v) }
                        size = num(1).takeIf { it != 0.0 } ?: 1.0
                    }
                    "Tm" -> if (operands.size >= 6) {
                        a = num(6); bb = num(5); c = num(4); d = num(3); e = num(2); f = num(1)
                        moved = true
                    }
                    "Td" -> move(num(2), num(1))
                    "TD" -> { leading = -num(1); move(num(2), num(1)) }
                    "TL" -> leading = num(1)
                    "T*" -> move(0.0, -leading)
                    "Tj" -> show(operands.lastOrNull())
                    "'" -> { move(0.0, -leading); show(operands.lastOrNull()) }
                    "\"" -> { move(0.0, -leading); show(operands.lastOrNull()) }
                    "TJ" -> {
                        val items = (operands.lastOrNull() as? PArr)?.items.orEmpty()
                        for (item in items) {
                            if (item is PStr) show(item) else if (item is PNum && item.v < -200) sink.gap()
                        }
                    }
                    "Do" -> (operands.lastOrNull() as? PName)?.let { xobject(resources, it.v, sink, depth, forms) }
                    "BI" -> lexer.skipInlineImage()
                }
                operands.clear()
            }
        }

        private fun xobject(resources: PDict?, name: String, sink: TextSink, depth: Int, forms: MutableSet<PStream>) {
            if (depth >= 6) return
            val all = resolve(resources?.get("XObject")) as? PDict ?: return
            val form = resolve(all[name]) as? PStream ?: return
            if ((resolve(form.dict["Subtype"]) as? PName)?.v != "Form" || !forms.add(form)) return
            val data = decode(form) ?: return
            sink.gap()
            interpret(data, (resolve(form.dict["Resources"]) as? PDict) ?: resources, sink, depth + 1, forms)
        }

        private fun fontFor(resources: PDict?, name: String): PdfFont? {
            val all = resolve(resources?.get("Font")) as? PDict ?: return null
            val font = resolve(all[name]) as? PDict ?: return null
            return fonts.getOrPut(font) { build(font) }
        }

        private fun build(font: PDict): PdfFont {
            val subtype = (resolve(font["Subtype"]) as? PName)?.v
            val composite = subtype == "Type0"
            val toUnicode = (resolve(font["ToUnicode"]) as? PStream)?.let { decode(it) }
                ?.let { ToUnicode.parse(it, if (composite) 2 else 1) }
            if (composite) {
                val charset = if (toUnicode == null) (resolve(font["Encoding"]) as? PName)?.v?.let { predefined(it) } else null
                return PdfFont(toUnicode, null, charset)
            }
            return PdfFont(toUnicode, simpleTable(font), null)
        }

        /** 单字节字体:按 WinAnsi 解,再照 /Differences 换掉写明的那几个码。 */
        private fun simpleTable(font: PDict): Array<String?> {
            val table = arrayOfNulls<String>(256)
            val cp1252 = runCatching { Charset.forName("windows-1252") }.getOrDefault(Charsets.ISO_8859_1)
            for (code in 32 until 256) table[code] = String(byteArrayOf(code.toByte()), cp1252)
            val encoding = resolve(font["Encoding"]) as? PDict
            val differences = encoding?.let { resolve(it["Differences"]) } as? PArr
            if (differences != null) {
                var code = 0
                for (item in differences.items) {
                    when (val x = resolve(item)) {
                        is PNum -> code = x.v.toInt()
                        is PName -> {
                            if (code in 0..255) Glyphs.unicode(x.v)?.let { table[code] = it }
                            code++
                        }
                        else -> {}
                    }
                }
            }
            return table
        }

        /** 预定义的 CMap 名字里能看出原来的编码时,直接按那种编码解(UCS-2、Big5、GBK、Shift_JIS……)。 */
        private fun predefined(name: String): Charset? {
            val charset = when {
                "UCS2" in name || "UTF16" in name -> "UTF-16BE"
                "UTF8" in name -> "UTF-8"
                "UTF32" in name -> "UTF-32BE"
                "B5" in name -> "Big5"
                name.startsWith("GBK2K") -> "GB18030"
                name.startsWith("GB") -> "GBK"
                "RKSJ" in name -> "Shift_JIS"
                name == "EUC-H" || name == "EUC-V" -> "EUC-JP"
                name.startsWith("KSC") -> "EUC-KR"
                else -> return null
            }
            return runCatching { Charset.forName(charset) }.getOrNull()
        }

        /** 解开流的过滤器;不认识的(多是图片的编码)为 null。整份文件解开的总量有上限,防压缩炸弹。 */
        fun decode(s: PStream): ByteArray? {
            var data = b.copyOfRange(s.start, s.end)
            val filters = when (val f = resolve(s.dict["Filter"])) {
                is PName -> listOf(f.v)
                is PArr -> f.items.mapNotNull { (resolve(it) as? PName)?.v }
                else -> emptyList()
            }
            for (filter in filters) {
                data = when (filter) {
                    "FlateDecode", "Fl" -> inflate(data) ?: return null
                    "ASCIIHexDecode", "AHx" -> asciiHex(data)
                    "ASCII85Decode", "A85" -> ascii85(data)
                    else -> return null
                }
            }
            decoded += data.size
            if (decoded > MAX_DECODED) throw DocumentText.TooLarge()
            return data
        }

        private fun inflate(data: ByteArray): ByteArray? = inflate(data, nowrap = false) ?: inflate(data, nowrap = true)

        /** 解到哪算哪:中途坏掉的流也交出已经解开的部分。 */
        private fun inflate(data: ByteArray, nowrap: Boolean): ByteArray? {
            val inflater = Inflater(nowrap)
            try {
                inflater.setInput(data)
                val out = ByteArrayOutputStream(minOf(maxOf(data.size * 3, 1024), 1 shl 20))
                val buf = ByteArray(32 * 1024)
                var stalls = 0
                while (!inflater.finished()) {
                    val n = try { inflater.inflate(buf) } catch (e: DataFormatException) { break }
                    if (n > 0) {
                        out.write(buf, 0, n)
                        if (out.size() > MAX_STREAM) throw DocumentText.TooLarge()
                        stalls = 0
                    } else if (inflater.needsInput() || inflater.needsDictionary() || ++stalls > 2) break
                }
                return if (out.size() == 0) null else out.toByteArray()
            } finally {
                inflater.end()
            }
        }

        private fun asciiHex(data: ByteArray): ByteArray {
            val out = ByteArrayOutputStream(data.size / 2 + 1)
            var high = -1
            for (x in data) {
                val c = x.toInt() and 0xFF
                if (c == '>'.code) break
                val v = hexValue(c)
                if (v < 0) continue
                if (high < 0) high = v else { out.write(high * 16 + v); high = -1 }
            }
            if (high >= 0) out.write(high * 16)
            return out.toByteArray()
        }

        private fun ascii85(data: ByteArray): ByteArray {
            val out = ByteArrayOutputStream(data.size)
            val group = IntArray(5)
            var n = 0
            var i = if (data.size >= 2 && data[0] == '<'.code.toByte() && data[1] == '~'.code.toByte()) 2 else 0
            fun flush(count: Int) {
                var v = 0L
                for (k in 0 until 5) v = v * 85 + group[k]
                for (k in 0 until count) out.write(((v shr (24 - 8 * k)) and 0xFF).toInt())
            }
            while (i < data.size) {
                val c = data[i++].toInt() and 0xFF
                if (c == '~'.code) break
                if (isSpace(c)) continue
                if (c == 'z'.code && n == 0) { repeat(4) { out.write(0) }; continue }
                if (c < '!'.code || c > 'u'.code) continue
                group[n++] = c - '!'.code
                if (n == 5) { flush(4); n = 0 }
            }
            if (n > 1) {
                for (k in n until 5) group[k] = 84
                flush(n - 1)
            }
            return out.toByteArray()
        }
    }

    private val OBJ = "obj".toByteArray(Charsets.ISO_8859_1)
    private val TRAILER = "trailer".toByteArray(Charsets.ISO_8859_1)
    private val ENDSTREAM = "endstream".toByteArray(Charsets.ISO_8859_1)
}

/** 一页的字:同一行的接着写,换了行就换行;位置跳开的两段拉丁字母之间补一个空格(中日韩的字之间不补)。 */
private class TextSink {
    private val sb = StringBuilder()
    private var gap = false

    fun gap() { gap = true }

    fun newline() {
        gap = false
        while (sb.isNotEmpty() && sb[sb.length - 1] == ' ') sb.setLength(sb.length - 1)
        if (sb.isNotEmpty() && sb[sb.length - 1] != '\n') sb.append('\n')
    }

    fun text(s: String) {
        if (s.isEmpty() || sb.length >= DocumentText.MAX_CHARS) return
        if (gap && sb.isNotEmpty()) {
            val last = sb[sb.length - 1]
            val first = s[0]
            if (!last.isWhitespace() && !first.isWhitespace() && !(cjk(last) || cjk(first)) && first !in CLOSING && last !in OPENING) sb.append(' ')
        }
        gap = false
        sb.append(s)
    }

    fun result(): String = sb.toString()

    private fun cjk(c: Char): Boolean = c.code in 0x2E80..0x9FFF || c.code in 0xAC00..0xD7AF || c.code in 0xF900..0xFAFF || c.code in 0xFF00..0xFFEF

    private companion object {
        const val CLOSING = ",.;:!?)]}%"
        const val OPENING = "([{"
    }
}

// ---------- Word、Excel、PowerPoint(Office Open XML) ----------

/** 逐个收 XML 的标签和字(见 [Ooxml.scan]);标签名带前缀,比较时用 [Ooxml.local]。 */
private abstract class XmlHandler {
    open fun tag(name: String, closing: Boolean, empty: Boolean, attrs: String) {}
    open fun text(s: String) {}
}

private object Ooxml {
    private const val MAX_PART = 64 shl 20
    private const val MAX_PARTS = 160L shl 20
    private const val MAX_COLUMNS = 256
    private val SLIDE = Regex("^ppt/slides/slide(\\d+)\\.xml$")
    private val SHEET = Regex("^xl/worksheets/sheet(\\d+)\\.xml$")
    private val REL_ID = Regex("(?:^|\\s)[A-Za-z0-9_]+:id\\s*=\\s*(\"([^\"]*)\"|'([^']*)')")

    fun docx(bytes: ByteArray, deadline: Long): DocumentText.Result {
        val names = setOf("word/document.xml", "word/footnotes.xml", "word/endnotes.xml")
        val parts = parts(bytes, deadline) { it in names }
        val main = parts["word/document.xml"] ?: return DocumentText.Result.Unreadable("document_unreadable", DocumentText.DAMAGED)
        val sb = StringBuilder()
        val paragraphs = word(String(main, Charsets.UTF_8), sb)
        for ((part, label) in listOf("word/footnotes.xml" to "footnotes", "word/endnotes.xml" to "endnotes")) {
            val xml = parts[part] ?: continue
            val notes = StringBuilder()
            word(String(xml, Charsets.UTF_8), notes)
            val cleaned = DocumentText.clean(notes.toString())
            if (DocumentText.hasText(cleaned)) sb.append("\n\n--- ").append(label).append(" ---\n").append(cleaned)
        }
        val text = DocumentText.clean(sb.toString())
        if (!DocumentText.hasText(text)) return DocumentText.Result.Unreadable("document_no_text", DocumentText.EMPTY)
        return DocumentText.text(text, "paragraphs", paragraphs, text.length >= DocumentText.MAX_CHARS)
    }

    /** Word 的正文:w:t 里的字;一段一行,表格的格子用 Tab 隔开、一列一行。返回段落数。 */
    private fun word(xml: String, sb: StringBuilder): Int {
        val handler = object : XmlHandler() {
            var inText = false
            var runs = 0
            var cells = 0
            var paragraphs = 0

            override fun tag(name: String, closing: Boolean, empty: Boolean, attrs: String) {
                when (local(name)) {
                    "t" -> inText = !closing && !empty
                    "r" -> if (closing) runs = maxOf(0, runs - 1) else if (!empty) runs += 1
                    "tab" -> if (!closing && runs > 0) sb.append('\t')
                    "br", "cr" -> if (!closing && runs > 0) sb.append('\n')
                    "p" -> if (closing || empty) {
                        paragraphs += 1
                        sb.append(if (cells > 0) ' ' else '\n')
                    }
                    "tc" -> if (closing) {
                        cells = maxOf(0, cells - 1)
                        while (sb.isNotEmpty() && sb[sb.length - 1] == ' ') sb.setLength(sb.length - 1)
                        sb.append('\t')
                    } else if (!empty) cells += 1
                    "tr" -> if (closing) {
                        trimEnd(sb)
                        sb.append('\n')
                    }
                }
            }

            override fun text(s: String) {
                if (inText) sb.append(s)
            }
        }
        scan(xml, handler)
        return handler.paragraphs
    }

    private fun trimEnd(sb: StringBuilder) {
        while (sb.isNotEmpty() && (sb[sb.length - 1] == '\t' || sb[sb.length - 1] == ' ')) sb.setLength(sb.length - 1)
    }

    fun xlsx(bytes: ByteArray, deadline: Long): DocumentText.Result {
        val parts = parts(bytes, deadline) {
            it == "xl/sharedStrings.xml" || it == "xl/workbook.xml" || it == "xl/_rels/workbook.xml.rels" || SHEET.matches(it)
        }
        val shared = parts["xl/sharedStrings.xml"]?.let { sharedStrings(String(it, Charsets.UTF_8)) }.orEmpty()
        val sheets = ordered(parts, "xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/", "sheet", "name", SHEET) { n -> "Sheet$n" }
        if (sheets.isEmpty()) return DocumentText.Result.Unreadable("document_unreadable", DocumentText.DAMAGED)
        val sb = StringBuilder()
        var any = false
        for ((i, sheet) in sheets.withIndex()) {
            DocumentText.checkTime(deadline)
            if (sb.length >= DocumentText.MAX_CHARS) break
            val xml = parts[sheet.second] ?: continue
            if (i > 0) sb.append("\n\n")
            sb.append("--- sheet ").append(sheet.first).append(" ---\n")
            val body = StringBuilder()
            cells(String(xml, Charsets.UTF_8), shared, body)
            if (DocumentText.hasText(body.toString())) any = true
            sb.append(body)
        }
        if (!any) return DocumentText.Result.Unreadable("document_no_text", DocumentText.EMPTY)
        val text = DocumentText.clean(sb.toString())
        return DocumentText.text(text, "sheets", sheets.size, text.length >= DocumentText.MAX_CHARS)
    }

    private fun sharedStrings(xml: String): List<String> {
        val out = ArrayList<String>()
        val current = StringBuilder()
        scan(xml, object : XmlHandler() {
            var inItem = false
            var inText = false
            var phonetic = false

            override fun tag(name: String, closing: Boolean, empty: Boolean, attrs: String) {
                when (local(name)) {
                    "si" -> if (empty) {
                        out.add("")
                    } else if (closing) {
                        out.add(current.toString())
                        current.setLength(0)
                        inItem = false
                    } else {
                        inItem = true
                    }
                    "t" -> inText = !closing && !empty
                    "rPh" -> phonetic = !closing && !empty
                }
            }

            override fun text(s: String) {
                if (inItem && inText && !phonetic) current.append(s)
            }
        })
        return out
    }

    /** 一张工作表:一列一行,格子之间用 Tab;按格子的位置补上空格子(最多 [MAX_COLUMNS] 列)。 */
    private fun cells(xml: String, shared: List<String>, sb: StringBuilder) {
        val row = ArrayList<Pair<Int, String>>()
        val value = StringBuilder()
        scan(xml, object : XmlHandler() {
            var type = ""
            var column = 0
            var next = 0
            var inValue = false
            var inInline = false
            var inText = false

            override fun tag(name: String, closing: Boolean, empty: Boolean, attrs: String) {
                when (local(name)) {
                    "row" -> {
                        if (closing || empty) flush(row, sb)
                        row.clear()
                        next = 0
                    }
                    "c" -> if (!closing) {
                        type = attr(attrs, "t").orEmpty()
                        column = columnOf(attr(attrs, "r")) ?: next
                        value.setLength(0)
                        if (empty) next = column + 1
                    } else {
                        val shown = cellText(type, value.toString(), shared)
                        if (shown.isNotEmpty()) row.add(column to shown)
                        next = column + 1
                    }
                    "v" -> inValue = !closing && !empty
                    "is" -> inInline = !closing && !empty
                    "t" -> inText = !closing && !empty
                }
            }

            override fun text(s: String) {
                if (inValue || (inInline && inText)) value.append(s)
            }
        })
        flush(row, sb)
    }

    private fun flush(row: List<Pair<Int, String>>, sb: StringBuilder) {
        val sorted = row.filter { it.first < MAX_COLUMNS }.sortedBy { it.first }
        if (sorted.isEmpty()) return
        var col = 0
        for ((c, text) in sorted) {
            while (col < c) {
                sb.append('\t')
                col++
            }
            sb.append(text.replace('\t', ' ').replace('\n', ' '))
        }
        sb.append('\n')
    }

    private fun cellText(type: String, raw: String, shared: List<String>): String = when (type) {
        "s" -> raw.trim().toIntOrNull()?.let { shared.getOrNull(it) }.orEmpty()
        "b" -> when (raw.trim()) {
            "1" -> "TRUE"
            "0" -> "FALSE"
            else -> raw
        }
        else -> raw
    }

    private fun columnOf(ref: String?): Int? {
        val letters = ref?.takeWhile { it.isLetter() }?.uppercase() ?: return null
        if (letters.isEmpty() || letters.length > 3) return null
        return letters.fold(0) { acc, ch -> acc * 26 + (ch - 'A' + 1) } - 1
    }

    fun pptx(bytes: ByteArray, deadline: Long): DocumentText.Result {
        val parts = parts(bytes, deadline) {
            it == "ppt/presentation.xml" || it == "ppt/_rels/presentation.xml.rels" || SLIDE.matches(it)
        }
        val slides = ordered(parts, "ppt/presentation.xml", "ppt/_rels/presentation.xml.rels", "ppt/", "sldId", null, SLIDE) { n -> n.toString() }
        if (slides.isEmpty()) return DocumentText.Result.Unreadable("document_unreadable", DocumentText.DAMAGED)
        val sb = StringBuilder()
        var any = false
        for ((i, slide) in slides.withIndex()) {
            DocumentText.checkTime(deadline)
            if (sb.length >= DocumentText.MAX_CHARS) break
            val xml = parts[slide.second] ?: continue
            if (i > 0) sb.append("\n\n")
            sb.append("--- slide ").append(i + 1).append(" ---\n")
            val body = StringBuilder()
            slide(String(xml, Charsets.UTF_8), body)
            if (DocumentText.hasText(body.toString())) any = true
            sb.append(body)
        }
        if (!any) return DocumentText.Result.Unreadable("document_no_text", DocumentText.EMPTY)
        val text = DocumentText.clean(sb.toString())
        return DocumentText.text(text, "slides", slides.size, text.length >= DocumentText.MAX_CHARS)
    }

    private fun slide(xml: String, sb: StringBuilder) {
        scan(xml, object : XmlHandler() {
            var inText = false

            override fun tag(name: String, closing: Boolean, empty: Boolean, attrs: String) {
                when (local(name)) {
                    "t" -> inText = !closing && !empty
                    "p" -> if (closing || empty) sb.append('\n')
                    "br" -> if (!closing) sb.append('\n')
                    "tc" -> if (closing) sb.append('\t')
                    "tr" -> if (closing) sb.append('\n')
                }
            }

            override fun text(s: String) {
                if (inText) sb.append(s)
            }
        })
    }

    /**
     * 工作表、投影片的先后:照 workbook.xml / presentation.xml 里列的顺序,经 .rels 找到各自的文件;
     * 对不上时按文件名里的编号排。返回 (名字, 文件)。
     */
    private fun ordered(
        parts: Map<String, ByteArray>, index: String, rels: String, base: String, entryTag: String, nameAttr: String?,
        files: Regex, fallbackName: (Int) -> String,
    ): List<Pair<String, String>> {
        val targets = HashMap<String, String>()
        parts[rels]?.let { r ->
            scan(String(r, Charsets.UTF_8), object : XmlHandler() {
                override fun tag(name: String, closing: Boolean, empty: Boolean, attrs: String) {
                    if (closing || local(name) != "Relationship") return
                    val id = attr(attrs, "Id") ?: return
                    val target = attr(attrs, "Target") ?: return
                    targets[id] = if (target.startsWith("/")) target.removePrefix("/") else base + target
                }
            })
        }
        val listed = ArrayList<Pair<String, String>>()
        parts[index]?.let { x ->
            scan(String(x, Charsets.UTF_8), object : XmlHandler() {
                override fun tag(name: String, closing: Boolean, empty: Boolean, attrs: String) {
                    if (closing || local(name) != entryTag) return
                    val target = relId(attrs)?.let { targets[it] } ?: return
                    if (target !in parts) return
                    val shown = nameAttr?.let { attr(attrs, it) } ?: (listed.size + 1).toString()
                    listed.add(shown to target)
                }
            })
        }
        if (listed.isNotEmpty()) return listed
        return parts.keys.mapNotNull { k -> files.matchEntire(k)?.groupValues?.get(1)?.toIntOrNull()?.let { it to k } }
            .sortedBy { it.first }.map { (n, k) -> fallbackName(n) to k }
    }

    /** `r:id` 这类带前缀的 id 属性(不是 sheetId)。 */
    private fun relId(attrs: String): String? {
        val m = REL_ID.find(attrs) ?: return null
        return decode(m.groupValues[2].ifEmpty { m.groupValues[3] })
    }

    private fun attr(attrs: String, name: String): String? {
        val m = Regex("(?:^|\\s)" + Regex.escape(name) + "\\s*=\\s*(\"([^\"]*)\"|'([^']*)')").find(attrs) ?: return null
        return decode(m.groupValues[2].ifEmpty { m.groupValues[3] })
    }

    fun local(name: String): String = name.substringAfterLast(':')

    /** ZIP 里要的那几份(名字 → 内容);每份、合起来都有上限,防压缩炸弹。 */
    private fun parts(bytes: ByteArray, deadline: Long, wanted: (String) -> Boolean): Map<String, ByteArray> {
        val out = HashMap<String, ByteArray>()
        var total = 0L
        ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            val chunk = ByteArray(32 * 1024)
            while (true) {
                val entry = zip.nextEntry ?: break
                DocumentText.checkTime(deadline)
                if (entry.isDirectory || !wanted(entry.name)) continue
                val buf = ByteArrayOutputStream()
                while (true) {
                    val n = zip.read(chunk)
                    if (n < 0) break
                    buf.write(chunk, 0, n)
                    if (buf.size() > MAX_PART) throw DocumentText.TooLarge()
                }
                total += buf.size()
                if (total > MAX_PARTS) throw DocumentText.TooLarge()
                out[entry.name] = buf.toByteArray()
            }
        }
        return out
    }

    /**
     * 逐个读 XML 的标签和字,交给 [handler]:标签名(带前缀)、是不是收尾标签、是不是自闭合、属性原文;字解好实体。
     * 注释、处理指令、DOCTYPE 跳过,CDATA 当字。
     */
    fun scan(xml: String, handler: XmlHandler) {
        var i = 0
        val n = xml.length
        while (i < n) {
            val lt = xml.indexOf('<', i)
            if (lt < 0) {
                handler.text(decode(xml.substring(i)))
                return
            }
            if (lt > i) handler.text(decode(xml.substring(i, lt)))
            if (xml.startsWith("<!--", lt)) {
                val e = xml.indexOf("-->", lt + 4)
                i = if (e < 0) n else e + 3
                continue
            }
            if (xml.startsWith("<![CDATA[", lt)) {
                val e = xml.indexOf("]]>", lt + 9)
                handler.text(xml.substring(lt + 9, if (e < 0) n else e))
                i = if (e < 0) n else e + 3
                continue
            }
            if (xml.startsWith("<?", lt) || xml.startsWith("<!", lt)) {
                val e = xml.indexOf('>', lt)
                i = if (e < 0) n else e + 1
                continue
            }
            var j = lt + 1
            var quote = '\u0000'
            while (j < n) {
                val c = xml[j]
                if (quote != '\u0000') {
                    if (c == quote) quote = '\u0000'
                } else if (c == '"' || c == '\'') {
                    quote = c
                } else if (c == '>') {
                    break
                }
                j++
            }
            if (j >= n) return
            val body = xml.substring(lt + 1, j)
            val closing = body.startsWith("/")
            val empty = !closing && body.endsWith("/")
            val inner = body.removePrefix("/").removeSuffix("/")
            val nameEnd = inner.indexOfFirst { it.isWhitespace() }.let { if (it < 0) inner.length else it }
            handler.tag(inner.substring(0, nameEnd), closing, empty, inner.substring(nameEnd))
            i = j + 1
        }
    }

    /** XML 的实体(&lt; &amp; &#20013; &#x4E2D; ……)。 */
    private fun decode(s: String): String {
        if ('&' !in s) return s
        val sb = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '&') {
                val semi = s.indexOf(';', i)
                if (semi > i + 1 && semi - i <= 12) {
                    val replacement = entity(s.substring(i + 1, semi))
                    if (replacement != null) {
                        sb.append(replacement)
                        i = semi + 1
                        continue
                    }
                }
            }
            sb.append(c)
            i++
        }
        return sb.toString()
    }

    private fun entity(e: String): String? {
        when (e) {
            "lt" -> return "<"
            "gt" -> return ">"
            "amp" -> return "&"
            "quot" -> return "\""
            "apos" -> return "'"
        }
        val code = when {
            e.startsWith("#x") || e.startsWith("#X") -> e.substring(2).toIntOrNull(16)
            e.startsWith("#") -> e.substring(1).toIntOrNull()
            else -> null
        } ?: return null
        return if (Character.isValidCodePoint(code)) String(Character.toChars(code)) else null
    }
}
