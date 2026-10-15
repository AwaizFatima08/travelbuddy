package com.homilabs.travelbuddy.util

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * "Unlock with fingerprint/face". It only unlocks the Firebase session that is already
 * saved on the phone — the password is never stored.
 *
 * With a strong sensor, a Keystore key that is invalidated when fingerprints change is
 * used, so adding a new fingerprint forces the password again.
 * After 3 failed tries (or "Use password"), the caller signs out → password login.
 */
class BiometricGate(private val activity: FragmentActivity) {

    sealed interface Outcome {
        data object Success : Outcome
        /** Fall back to the password (3 failed tries, lockout, "Use password", fingerprint changed). */
        data class UsePassword(val reason: String) : Outcome
        /** User closed the prompt; stay on the lock screen. */
        data object Dismissed : Outcome
    }

    private val manager = BiometricManager.from(activity)

    val strong get() = manager.canAuthenticate(BIOMETRIC_STRONG) == BiometricManager.BIOMETRIC_SUCCESS
    val available get() = strong || manager.canAuthenticate(BIOMETRIC_WEAK) == BiometricManager.BIOMETRIC_SUCCESS

    fun authenticate(title: String, onResult: (Outcome) -> Unit) {
        if (!available) {
            onResult(Outcome.UsePassword("Fingerprint/face is not set up on this phone."))
            return
        }
        var cipher: Cipher? = null
        if (strong) {
            try {
                cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, getOrCreateKey()) }
            } catch (_: KeyPermanentlyInvalidatedException) {
                deleteKey()
                onResult(Outcome.UsePassword("Your fingerprints changed. Please log in with your password."))
                return
            } catch (_: Exception) {
                cipher = null // fall back to prompt without crypto
            }
        }

        var failures = 0
        var fellBack = false
        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    val c = result.cryptoObject?.cipher
                    if (c != null) {
                        try {
                            c.doFinal(byteArrayOf(1))
                        } catch (_: Exception) {
                            onResult(Outcome.UsePassword("Please log in with your password."))
                            return
                        }
                    }
                    onResult(Outcome.Success)
                }

                override fun onAuthenticationFailed() {
                    failures++
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (fellBack) return
                    when (errorCode) {
                        BiometricPrompt.ERROR_NEGATIVE_BUTTON ->
                            onResult(Outcome.UsePassword("Log in with your password."))
                        BiometricPrompt.ERROR_LOCKOUT, BiometricPrompt.ERROR_LOCKOUT_PERMANENT ->
                            onResult(Outcome.UsePassword("Too many tries. Log in with your password."))
                        BiometricPrompt.ERROR_USER_CANCELED, BiometricPrompt.ERROR_CANCELED ->
                            onResult(if (failures >= 3) Outcome.UsePassword("3 failed tries.") else Outcome.Dismissed)
                        else -> onResult(Outcome.UsePassword(errString.toString()))
                    }
                }
            }
        )
        // Watch failures: after the 3rd, close the prompt and fall back to the password.
        val watcher = object : Runnable {
            override fun run() {
                if (failures >= 3 && !fellBack) {
                    fellBack = true
                    prompt.cancelAuthentication()
                    onResult(Outcome.UsePassword("3 failed tries. Log in with your password."))
                } else if (!fellBack) {
                    activity.window.decorView.postDelayed(this, 250)
                }
            }
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle("Use your fingerprint or face")
            .setNegativeButtonText("Use password")
            .setAllowedAuthenticators(if (cipher != null) BIOMETRIC_STRONG else BIOMETRIC_WEAK)
            .setConfirmationRequired(false)
            .build()
        if (cipher != null) prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
        else prompt.authenticate(info)
        activity.window.decorView.postDelayed(watcher, 250)
    }

    private fun getOrCreateKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setUserAuthenticationRequired(true)
                .setInvalidatedByBiometricEnrollment(true)
                .build()
        )
        return gen.generateKey()
    }

    fun deleteKey() {
        runCatching { KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(KEY_ALIAS) }
    }

    private companion object {
        const val KEY_ALIAS = "tb_biometric_unlock"
    }
}
