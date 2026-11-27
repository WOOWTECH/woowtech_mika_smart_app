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
    /**
     * 1 = the original six colours (face was an eye style); 2 = woowtechbot's eleven-colour palette, where face is
     * 0 automatic / 1 white / 2 black. Profiles saved before the palette change read as 1, so nothing changes colour.
     */
    val palette: Int = 1,
) {
    fun valid() = robot in 0..2 && palette in 1..2 && color in 0 until (if (palette >= 2) COLORS else LEGACY_COLORS) && face in 0..2 &&
        (image == null || (image.length <= 700_000 && runCatching {
            val bytes = java.util.Base64.getDecoder().decode(image)
            bytes.size >= 3 && bytes[0] == 0xff.toByte() && bytes[1] == 0xd8.toByte()
        }.getOrDefault(false)))

    /** Index into the eleven-colour palette, whichever generation this profile was saved with. */
    fun colorIndex(): Int = if (palette >= 2) color else LEGACY_TO_CURRENT[color.coerceIn(0, LEGACY_COLORS - 1)]

    /** 0 automatic (dark ink on yellow, orange and silver, otherwise white), 1 white, 2 black. */
    fun faceMode(): Int = if (palette >= 2) face else 0

    /** The same look expressed in the current palette, for editing and saving. */
    fun upgraded(): BotUiProfile = if (palette >= 2) this else copy(color = colorIndex(), face = 0, palette = 2)

    companion object {
        const val COLORS = 11
        private const val LEGACY_COLORS = 6
        // blue-violet, teal, violet, orange, pink, grey (the old six) -> blue, teal, purple, orange, pink, silver
        private val LEGACY_TO_CURRENT = intArrayOf(1, 8, 4, 3, 6, 10)
    }
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
