package com.tunnely.vpn.vpn

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Persists the last Mihomo config (with the TUN fd left as 0) encrypted with an
 * AES-GCM key held in Android Keystore, so the Quick Settings tile can start
 * the tunnel without the Flutter UI running.
 */
class ConfigStore(context: Context) {
    private val file = File(context.noBackupFilesDir, "active_config.bin")
    private val metaFile = File(context.noBackupFilesDir, "active_server.txt")

    fun save(config: String, serverName: String?) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(config.toByteArray(Charsets.UTF_8))
        val tmp = File(file.path + ".tmp")
        tmp.outputStream().use {
            it.write(cipher.iv.size)
            it.write(cipher.iv)
            it.write(encrypted)
        }
        if (!tmp.renameTo(file)) {
            file.delete()
            tmp.renameTo(file)
        }
        metaFile.writeText(serverName ?: "")
    }

    fun load(): String? {
        if (!file.exists()) return null
        return try {
            val bytes = file.readBytes()
            val ivLen = bytes[0].toInt()
            val iv = bytes.copyOfRange(1, 1 + ivLen)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(bytes, 1 + ivLen, bytes.size - 1 - ivLen), Charsets.UTF_8)
        } catch (e: Exception) {
            // Key lost (e.g. restored device) or corrupted file: force re-sync from the UI.
            file.delete()
            null
        }
    }

    fun serverName(): String? = metaFile.takeIf { it.exists() }?.readText()?.ifEmpty { null }

    fun clear() {
        file.delete()
        metaFile.delete()
    }

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (ks.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "tunnely_config_key"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
