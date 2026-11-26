package com.wangzan101.mika.chat

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

/** Avatar only: the existing .title file remains the sole source of conversation names. */
@Serializable
data class BotUiProfile(
    val robot: Int = 0,
    val color: Int = 0,
    val face: Int = 0,
    val image: String? = null,
) {
    fun valid() = robot in 0..2 && color in 0..5 && face in 0..2 &&
        (image == null || (image.length <= 700_000 && runCatching {
            val bytes = java.util.Base64.getDecoder().decode(image)
            bytes.size >= 3 && bytes[0] == 0xff.toByte() && bytes[1] == 0xd8.toByte()
        }.getOrDefault(false)))
}

/** A sidecar covered by ConversationStore.delete's existing <id>.json.* cleanup. */
internal object BotUiProfileDisk {
    private val json = Json { ignoreUnknownKeys = true }
    fun read(file: File): BotUiProfile = runCatching {
        require(file.length() <= 710_000)
        json.decodeFromString<BotUiProfile>(file.readText()).also { require(it.valid()) }
    }.getOrDefault(BotUiProfile())

    fun write(file: File, profile: BotUiProfile): Boolean {
        if (!profile.valid()) return false
        val tmp = File(file.path + ".tmp")
        return runCatching {
            file.parentFile?.mkdirs()
            tmp.outputStream().use { output ->
                output.write(json.encodeToString(BotUiProfile.serializer(), profile).toByteArray())
                output.fd.sync()
            }
            check(tmp.renameTo(file))
        }.isSuccess.also { tmp.delete() }
    }
}
