package com.wangzan101.mika.woowbot

import android.app.Activity
import androidx.annotation.Keep
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning

@Keep
class DirectBotQrScanner : BotQrScanner {
    override fun scan(activity: Activity, result: (String?) -> Unit, failure: () -> Unit) {
        val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).enableAutoZoom().build()
        GmsBarcodeScanning.getClient(activity, options).startScan()
            .addOnSuccessListener { result(it.rawValue) }
            .addOnCanceledListener { result(null) }
            .addOnFailureListener { failure() }
    }
}
