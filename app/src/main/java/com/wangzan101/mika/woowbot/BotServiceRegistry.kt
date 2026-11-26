package com.wangzan101.mika.woowbot

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

@Serializable
data class BotService(
    val id: String,
    val name: String,
    val origin: String,
    val allowHttpLan: Boolean = false,
    val enabled: Boolean = true,
    val profileId: String = UUID.randomUUID().toString(),
) {
    val profileName: String get() = "woowbot_$profileId"
    val policy: BotOrigin get() = BotOrigin.parse(origin, allowHttpLan)
}

@Serializable
data class BotRegistryState(val services: List<BotService> = emptyList(), val retiredProfiles: List<String> = emptyList())

/** Only service metadata is serialized. Credentials remain entirely in each WebKit Profile. */
class BotServiceRegistry(private val storage: Storage) {
    interface Storage { fun read(): String?; fun write(value: String) }
    private val json = Json { ignoreUnknownKeys = true }
    private val mutable = MutableStateFlow(readState())
    val state: StateFlow<BotRegistryState> = mutable

    @Synchronized fun add(name: String, address: String, allowHttpLan: Boolean = false): BotService {
        require(mutable.value.services.size < MAX_SERVICES)
        val cleanName = name.trim()
        require(cleanName.length in 1..80 && cleanName.none { it.isISOControl() })
        val origin = BotOrigin.parse(address, allowHttpLan)
        val service = BotService(UUID.randomUUID().toString(), cleanName, origin.value, origin.insecureLan)
        save(mutable.value.copy(services = mutable.value.services + service))
        return service
    }

    @Synchronized fun setEnabled(id: String, enabled: Boolean) = update(id) { it.copy(enabled = enabled) }

    /** Rotate before any further opening, even when remote revocation is unavailable/offline. */
    @Synchronized fun logout(id: String) {
        val old = find(id) ?: return
        require(mutable.value.retiredProfiles.size < MAX_RETIRED)
        save(mutable.value.copy(
            services = mutable.value.services.map { if (it.id == id) it.copy(enabled = false, profileId = UUID.randomUUID().toString()) else it },
            retiredProfiles = mutable.value.retiredProfiles + old.profileName,
        ))
    }

    @Synchronized fun remove(id: String) {
        val old = find(id) ?: return
        require(mutable.value.retiredProfiles.size < MAX_RETIRED)
        save(mutable.value.copy(services = mutable.value.services.filterNot { it.id == id }, retiredProfiles = mutable.value.retiredProfiles + old.profileName))
    }

    @Synchronized fun acknowledgeDeleted(profile: String) = save(mutable.value.copy(retiredProfiles = mutable.value.retiredProfiles - profile))
    fun find(id: String): BotService? = mutable.value.services.find { it.id == id }
    private fun update(id: String, change: (BotService) -> BotService) = save(mutable.value.copy(services = mutable.value.services.map { if (it.id == id) change(it) else it }))
    private fun save(next: BotRegistryState) {
        storage.write(json.encodeToString(next)) // Failed persistence must not publish a successful change.
        mutable.value = next
    }
    private fun readState(): BotRegistryState {
        val raw = storage.read() ?: return BotRegistryState()
        require(raw.length <= MAX_STORAGE)
        return json.decodeFromString<BotRegistryState>(raw).also { state ->
            require(state.services.size <= MAX_SERVICES && state.retiredProfiles.size <= MAX_RETIRED)
            require(state.services.map { it.id }.distinct().size == state.services.size)
            require(state.services.map { it.profileId }.distinct().size == state.services.size)
            state.services.forEach {
                require(UUID.fromString(it.id).toString() == it.id && UUID.fromString(it.profileId).toString() == it.profileId)
                require(it.name.length in 1..80 && it.name.none(Char::isISOControl))
                require(it.policy.value == it.origin)
                require(it.profileName !in state.retiredProfiles)
            }
            state.retiredProfiles.forEach { require(it.matches(Regex("woowbot_[0-9a-f-]{36}"))) }
        }
    }
    companion object {
        const val MAX_SERVICES = 20
        const val MAX_RETIRED = 64
        const val MAX_STORAGE = 128 * 1024
    }
}
